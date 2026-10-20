local Modules=script.Parent
local Runtime=Modules.Runtime
local Limits=require(Runtime.Limits)
local Yield=require(Runtime.Yield)
local Base64=require(Runtime.Base64)
local ImageDecode=require(Runtime.ImageDecode)
local Materialize=require(Runtime.Materialize)
local Inbox=require(Modules.Transport.Inbox)
local Fetch=require(Modules.Transport.Fetch)
local Progress=require(Modules.Progress)
local Resolve=require(Modules.Targets.Resolve)
local Persist=require(Modules.Targets.Persist)
local Image2D=require(Modules.Targets.Image2D)
local Mesh3D=require(Modules.Targets.Mesh3D)
local Media=require(Modules.Targets.Media)
local Probe=require(Modules.Media.Probe)
local OpenCloud=require(Modules.Media.OpenCloud)
local HttpService=game:GetService("HttpService")
local RunService=game:GetService("RunService")

local LiveToken=require(Runtime.LiveToken)

local Api={VERSION="1.5.0",RUNTIME_VERSION=Limits.VERSION}

 
local function liveSessionState()
	local ok,state=pcall(function()
		local bridge=game:GetService("CoreGui"):FindFirstChild("LiveSessionBridge")
		return bridge and bridge:GetAttribute("State") or nil
	end)
	if ok then return state end
	return nil
end

local KINDS={image=true,mesh=true,audio=true,video=true}
local KIND_ALIASES={
	["2d"]="image",texture="image",picture="image",png="image",jpg="image",jpeg="image",
	["3d"]="mesh",model="mesh",glb="mesh",gltf="mesh",
	sound="audio",music="audio",sfx="audio",mp3="audio",ogg="audio",wav="audio",flac="audio",
	movie="video",film="video",mp4="video",mov="video",
}
local DEFAULT_NAMES={image="Imagem",mesh="Modelo",audio="Audio",video="Video"}
 
local PROMOTED_OPTIONS={"layout","split","groups","rename","rest","expect","strict","rig","skinning","bones","stripPrefix","controller","assetId","openCloud","looped","loop","volume","playing","autoplay","output","width","height","force","pending","stash","upload","description","class","scale","center","ground","centerY","collision","anchored","canCollide","doubleSided","maxSize"}

local function workerAlive()
	local ok,root=pcall(Inbox.root)
	local beat=ok and root:GetAttribute("WorkerHeartbeat") or nil
	return type(beat)=="number" and os.time()-beat<10
end

 
local function firstLine(err)
	if type(err)=="table" then
		local text=err.message or err.error or err.code
		if text~=nil then return tostring(text):match("^[^\n]+") or tostring(text) end
	end
	return tostring(err):match("^[^\n]+") or tostring(err)
end

local function hasSource(spec)
	return typeof(spec.bytes)=="buffer" or spec.upload~=nil or spec.data~=nil or spec.text~=nil or spec.url~=nil
end

local function loadBytes(spec,yield)
	assert(type(spec)=="table","Fonte invalida.")
	if typeof(spec.bytes)=="buffer" then
		assert(buffer.len(spec.bytes)>0,"Campo bytes vazio.")
		return spec.bytes,spec.fileName or spec.name
	end
	if spec.upload then
		local bytes=Inbox.bytes(spec.upload,yield)
		local job=Inbox.get(spec.upload)
		return bytes,spec.fileName or job:GetAttribute("FileName")
	end
	if spec.data then
		assert(type(spec.data)=="string" and #spec.data>0,"Campo data vazio.")
		return Base64.decode(spec.data,yield,Limits.MAX_BYTES),spec.fileName or spec.name
	end
	if spec.text then
		assert(type(spec.text)=="string" and #spec.text>0,"Campo text vazio.")
		return buffer.fromstring(spec.text),spec.fileName or spec.name
	end
	if spec.url then
		local bytes,name=Fetch.bytes(spec.url)
		return bytes,spec.fileName or name
	end
	error("Informe a fonte: bytes=<buffer>, upload=<id>, data=<base64>, text=<string> ou url=<https://...> (ou assetId para audio/video ja publicado).")
end

local function detectKind(bytes,fileName)
	if ImageDecode.kind(bytes) then return "image" end
	if Mesh3D.matches(bytes) then return "mesh" end
	local media=Probe.inspect(bytes,fileName)
	if media then return media.kind end
	local lowered=string.lower(tostring(fileName or ""))
	if lowered:match("%.gl[bt]f?$") then return "mesh" end
	local byName=Probe.kindFromName(fileName)
	if byName then return byName end
	error("Formato nao reconhecido. Envie PNG, JPEG, GLB/GLTF, MP3/OGG/WAV/FLAC ou MP4/MOV.")
end

local function normalizeKind(kind)
	kind=string.lower(tostring(kind))
	kind=KIND_ALIASES[kind] or kind
	assert(KINDS[kind],"Tipo invalido: use image, mesh, audio, video ou auto.")
	return kind
end

local function resolveKind(request,bytes,fileName)
	local kind=request.kind
	if kind==nil or kind=="auto" then
		if bytes then
			kind=detectKind(bytes,fileName)
		else
			kind=Probe.kindFromName(fileName)
			assert(kind,"Com assetId informe kind='audio' ou 'video'.")
		end
	end
	return normalizeKind(kind)
end

local function promoteOptions(request)
	local options=type(request.options)=="table" and request.options or {}
	for _,key in ipairs(PROMOTED_OPTIONS) do
		if options[key]==nil and request[key]~=nil then options[key]=request[key] end
	end
	request.options=options
	return options
end

local function externals(list,yield)
	local out={}
	if type(list)~="table" then return out end
	for _,entry in ipairs(list) do
		local bytes,name=loadBytes(entry,yield)
		local key=string.lower(tostring(entry.name or name or ""):match("([^/\\]+)$") or "")
		assert(#key>0,"Arquivo externo sem nome.")
		out[key]=bytes
	end
	return out
end

local function cleanup(request)
	if request.upload and request.cleanup~=false then Inbox.remove(request.upload) end
	if type(request.externals)=="table" and request.cleanup~=false then
		for _,entry in ipairs(request.externals) do
			if entry.upload then Inbox.remove(entry.upload) end
		end
	end
end

local function isMediaRequest(request)
	if request.assetId~=nil or (type(request.options)=="table" and request.options.assetId~=nil) then return true end
	local kind=request.kind
	if kind==nil or kind=="auto" then return false end
	local ok,normalized=pcall(normalizeKind,kind)
	return ok and (normalized=="audio" or normalized=="video")
end

function Api.execute(request,ctx)
	assert(type(request)=="table","Requisicao invalida.")
	ctx=ctx or {}
	local slice=ctx.slice or Limits.PLUGIN_SLICE or Limits.SLICE
	local yield=Progress.wrapYield(ctx.yield or Yield.ticker(ctx.check,slice))
	local started=os.clock()
	local began=false
	local ok,instance,report=pcall(function()
		local options=promoteOptions(request)
		local bytes,fileName
		if hasSource(request) then
			bytes,fileName=loadBytes(request,yield)
		else
			assert(options.assetId~=nil,"Informe a fonte (url, data, upload, text) ou, para audio/video ja publicado, assetId.")
			fileName=request.fileName or request.name
		end
		local kind=resolveKind(request,bytes,fileName)
		local name=request.name or Resolve.baseName(fileName,DEFAULT_NAMES[kind])
		Progress.begin({id=ctx.jobId or request.upload,name=name,kind=kind,bytes=bytes and buffer.len(bytes) or 0,source=ctx.source})
		began=true
		Materialize.mode(request.persist)
		local job={name=name,fileName=fileName,bytes=bytes,target=request.target or {},options=options,persist=request.persist,fallback=request.fallback,kind=kind}
		local pipeline={yield=yield,check=ctx.check,stage=Progress.stage}
		local instance,report
		if kind=="image" then
			instance,report=Image2D.import(job,pipeline)
		elseif kind=="mesh" then
			job.externals=externals(request.externals,yield)
			instance,report=Mesh3D.import(job,pipeline)
		else
			job.assetId=request.assetId
			instance,report=Media.import(job,pipeline)
		end
		Progress.stage("finalizando")
		cleanup(request)
		report.ok=true
		report.kind=report.kind or kind
		report.path=instance:GetFullName()
		report.name=instance.Name
		report.class=instance.ClassName
		report.inputBytes=bytes and buffer.len(bytes) or 0
		report.ms=math.round((os.clock()-started)*1000)
		return instance,report
	end)
	if not ok then
		if began then Progress.finish(false,firstLine(instance)) end
		error(instance,0)
	end
	Progress.finish(true,report.path)
	return instance,report
end

local function decodeRequest(request)
	if type(request)=="string" then
		local ok,decoded=pcall(HttpService.JSONDecode,HttpService,request)
		assert(ok and type(decoded)=="table","Requisicao JSON invalida.")
		request=decoded
	end
	assert(type(request)=="table","Requisicao invalida.")
	return request
end

local function enqueue(request)
	local id=request.upload or Inbox.begin(Inbox.newId("job"),{name=request.name or "job"})
	Inbox.setState(id,"queued",{Request=request,Result=nil,Error=nil,Queued=os.time()})
	return id
end

local function failure(err)
	local detail=type(err)=="table" and (err.detail or err.message) or err
	return {ok=false,error=firstLine(err),code=type(err)=="table" and err.code or nil,detail=tostring(detail):sub(1,2000)}
end

 
 
function Api.import(request,ctx)
	request=decodeRequest(request)
	if request.mode=="queue" then
		local id=enqueue(request)
		return {ok=true,queued=true,id=id,hint="Use Api.result('"..id.."') para acompanhar; requer o plugin ImportMCP ativo no Studio."}
	end
	assert(not RunService:IsRunning(),"Pare o Play antes de importar.")
	ctx=type(ctx)=="table" and table.clone(ctx) or {}
	ctx.source=ctx.source or "mcp"
	 
	 
	 
	local okMode,mode=pcall(Materialize.mode,request.persist)
	if ctx.source~="plugin" and request.sync~=true and okMode and mode=="asset" and workerAlive() and not isMediaRequest(request) then
		local id=enqueue(request)
		return {ok=true,queued=true,id=id,mode="asset",hint="Modo asset: o plugin ImportMCP processa o upload permanente. Consulte Api.result('"..id.."') ate done=true; o relatorio traz path e assetIds."}
	end
	local ok,instance,report=pcall(Api.execute,request,ctx)
	if not ok then return failure(instance) end
	return report
end

function Api.importMany(list,common)
	list=decodeRequest(list)
	if list.items then common=common or list.common list=list.items end
	assert(type(list)=="table" and #list>0,"Informe uma lista de requisicoes.")
	local ids={}
	for index,item in ipairs(list) do
		local request={}
		for key,value in pairs(common or {}) do request[key]=value end
		for key,value in pairs(item) do request[key]=value end
		request.mode=nil
		ids[index]=enqueue(request)
	end
	return {ok=true,queued=#ids,ids=ids,hint="A fila processa um por vez no plugin; acompanhe com Api.progress() ou Api.result(id)."}
end

 
 
 
function Api.inspect(request,ctx)
	request=decodeRequest(request)
	ctx=type(ctx)=="table" and ctx or {}
	local yield=ctx.yield or Yield.ticker(ctx.check,ctx.slice or Limits.PLUGIN_SLICE or Limits.SLICE)
	local started=os.clock()
	local ok,result=pcall(function()
		local options=promoteOptions(request)
		local bytes,fileName=loadBytes(request,yield)
		local kind=resolveKind(request,bytes,fileName)
		local name=request.name or Resolve.baseName(fileName,DEFAULT_NAMES[kind])
		local report
		if kind=="mesh" then
			local job={name=name,fileName=fileName,bytes=bytes,options=options,externals=externals(request.externals,yield)}
			report=Mesh3D.inspect(job,{yield=yield,check=ctx.check})
			report.hint=report.ok and "Layout compativel com expect (ou sem expect). Importe com as mesmas opcoes." or "Ajuste split/groups/rename/expect e chame Api.plan de novo antes de importar."
		elseif kind=="image" then
			local info=ImageDecode.probe(bytes)
			report={ok=info~=nil,image=info,format=ImageDecode.kind(bytes)}
		else
			local info,err=Probe.inspect(bytes,fileName)
			assert(info,"Arquivo nao reconhecido como audio/video ("..tostring(err)..").")
			local problems=Probe.problems(info)
			report={ok=#problems==0,media=info,problems=problems,openCloud=OpenCloud.status()}
		end
		if request.cleanup==true then cleanup(request) end
		report.kind=kind
		report.name=name
		report.fileName=fileName
		report.inputBytes=buffer.len(bytes)
		report.ms=math.round((os.clock()-started)*1000)
		return report
	end)
	if not ok then return failure(result) end
	return result
end

 
function Api.plan(request,ctx)
	return Api.inspect(request,ctx)
end

function Api.result(id)
	local job=Inbox.find(id)
	if not job then return {ok=false,error="Job '"..tostring(id).."' nao existe (ja concluido e removido, ou id errado)."} end
	local info=Inbox.describe(job)
	for _,key in ipairs({"Request","Result"}) do
		if type(info[key])=="string" then
			local okDecode,decoded=pcall(HttpService.JSONDecode,HttpService,info[key])
			if okDecode then info[key]=decoded end
		end
	end
	info.ok=info.State~="failed"
	info.done=info.State=="done" or info.State=="failed"
	return info
end

function Api.progress()
	local snapshot=Progress.snapshot()
	snapshot.ok=true
	snapshot.queued=#Inbox.list("queued")
	snapshot.running=#Inbox.list("running")
	return snapshot
end

Api.upload={}

function Api.upload.begin(id,meta)
	if type(id)=="table" then meta=id id=nil end
	return {ok=true,id=Inbox.begin(id,meta),chunkHint="Envie pedacos base64 de ate 200000 caracteres por chamada com Api.upload.append(id, chunk) e finalize com Api.upload.finish(id)."}
end

function Api.upload.append(id,chunk)
	local info=Inbox.append(id,chunk)
	info.ok=true
	return info
end

function Api.upload.finish(id)
	local info=Inbox.finish(id)
	info.ok=true
	return info
end

function Api.upload.cancel(id)
	return {ok=Inbox.remove(id)}
end

function Api.upload.list(state)
	return Inbox.list(state)
end

function Api.upload.clear(keepUnfinished)
	return {ok=true,removed=Inbox.clear(keepUnfinished)}
end

 
Api.media={}

function Api.media.pending()
	return {ok=true,items=Media.pending()}
end

function Api.media.bind(path,assetId)
	local ok,result=pcall(function()
		local instance=Resolve.instance(path,false)
		return Media.bind(instance,assetId)
	end)
	if not ok then return failure(result) end
	return result
end

function Api.media.upload(path,options,ctx)
	options=type(options)=="table" and options or {}
	ctx=type(ctx)=="table" and ctx or {}
	local ok,result=pcall(function()
		assert(not RunService:IsRunning(),"Pare o Play antes de enviar.")
		local instance=Resolve.instance(path,false)
		return Media.upload(instance,options,{check=ctx.check,yield=ctx.yield})
	end)
	if not ok then return failure(result) end
	return result
end

function Api.media.operation(operationId,apiKey)
	local ok,result=pcall(OpenCloud.operation,operationId,apiKey)
	if not ok then return failure(result) end
	return result
end

 
 
function Api.setOpenCloud(options)
	options=decodeRequest(options)
	local ok,result=pcall(OpenCloud.configure,options)
	if not ok then return failure(result) end
	result.ok=true
	return result
end

function Api.install(force)
	local runtime,installed=Persist.installRuntime(force==true)
	Inbox.root()
	return {ok=true,runtime=runtime:GetFullName(),installedNow=installed,version=Limits.VERSION,inbox=Inbox.root():GetFullName()}
end

function Api.restore(path)
	local instance=Resolve.instance(path,false)
	local ok,err=pcall(Persist.restore,instance)
	if not ok then return {ok=false,path=instance:GetFullName(),error=firstLine(err)} end
	return {ok=true,path=instance:GetFullName(),status=instance:GetAttribute("ImportMCP_Status")}
end

 
function Api.restoreAll(options)
	local report=Persist.restoreAll(type(options)=="table" and options or nil)
	report.ok=report.failed==0
	return report
end

function Api.restoreMissing()
	return Api.restoreAll({onlyMissing=true})
end

 
 
function Api.live()
	local summary=Persist.liveSummary()
	summary.ok=true
	summary.liveSession=liveSessionState()
	summary.tokenAttribute=LiveToken.ATTRIBUTE
	return summary
end

function Api.list()
	local out=Persist.list()
	for _,item in ipairs(Media.pending()) do
		out[#out+1]={path=item.path,class=item.class,kind=item.kind=="audio" and "Audio" or "Video",mode="pending",status="PendingUpload",bytes=item.bytes,error=item.reason}
	end
	return out
end

function Api.remove(path,keepInstance)
	local instance=Resolve.instance(path,false)
	if keepInstance then
		Persist.detach(instance)
		return {ok=true,detached=instance:GetFullName()}
	end
	local name=instance:GetFullName()
	instance:Destroy()
	return {ok=true,removed=name}
end

function Api.status()
	local runtime=Persist.runtimeStatus()
	return {
		ok=true,version=Api.VERSION,runtime=runtime,inbox=Inbox.root():GetFullName(),uploads=#Inbox.list(),queued=#Inbox.list("queued"),
		imports=#Persist.tagged(),permanent=#Persist.permanent(),pendingMedia=#Media.pending(),mode=Materialize.default(),createAsset=Materialize.availability(),
		openCloud=OpenCloud.status(),workerAlive=workerAlive(),playing=RunService:IsRunning(),progress=Progress.snapshot(),
		liveSession=liveSessionState(),
		kinds={"image","mesh","audio","video"},
		limits={maxBytes=Limits.MAX_BYTES,maxTexture=Limits.MAX_TEXTURE,vertices=Limits.VERTICES,triangles=Limits.TRIANGLES,uploadsPerMinute=Limits.UPLOADS_PER_MINUTE,maxBones=Limits.MAX_BONES,chunkTriangles=Limits.CHUNK_TRIANGLES,autoNodeLimit=Limits.AUTO_NODE_LIMIT,maxAudioBytes=Limits.MAX_AUDIO_BYTES,audioMaxSeconds=Limits.AUDIO_MAX_SECONDS,videoMaxSeconds=Limits.VIDEO_MAX_SECONDS},
	}
end

 
 
function Api.setMode(mode)
	assert(mode=="asset" or mode=="session","Modo invalido: use 'asset' ou 'session'.")
	return {ok=true,mode=Materialize.setDefault(mode)}
end

function Api.help()
	local ok,readme=pcall(function() return script.Parent.Parent.Parent:FindFirstChild("LEIA_ME") end)
	if ok and readme then return readme.Value end
	local stored=game:GetService("ServerStorage"):FindFirstChild("ImportMCP")
	readme=stored and stored:FindFirstChild("LEIA_ME")
	return readme and readme.Value or "Consulte ServerStorage.ImportMCP.LEIA_ME."
end

return table.freeze(Api)
