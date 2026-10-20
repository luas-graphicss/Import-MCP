local Runtime=script.Parent.Parent.Runtime
local Limits=require(Runtime.Limits)
local Store=require(Runtime.Store)
local Materialize=require(Runtime.Materialize)
local Yield=require(Runtime.Yield)
local Probe=require(script.Parent.Parent.Media.Probe)
local OpenCloud=require(script.Parent.Parent.Media.OpenCloud)
local Resolve=require(script.Parent.Resolve)
local Props=require(script.Parent.Props)
local CollectionService=game:GetService("CollectionService")
local SoundService=game:GetService("SoundService")

 
 
 
 
 
local Media={}

Media.classes={audio={"Sound","AudioPlayer"},video={"VideoFrame","VideoPlayer"}}

local FORMATS={audio="AUD1",video="VID1"}
local KIND_NAMES={audio="Audio",video="Video"}

local NEW_VIDEO_HINT="ative File > Beta Features > New Video API ou use class='VideoFrame'"

local function assetUri(assetId)
	return "rbxassetid://"..tostring(assetId)
end

local function create(className,hint)
	local ok,instance=pcall(Instance.new,className)
	if not ok then error(className.." indisponivel neste Studio"..(hint and ("; "..hint) or "")..".",0) end
	return instance
end

function Media.parseAssetId(value)
	if value==nil then return nil end
	if type(value)=="number" then return value>0 and math.floor(value) or nil end
	local text=tostring(value)
	local id=text:match("rbxassetid://(%d+)") or text:match("[?&]id=(%d+)") or text:match("/(%d+)/?$") or text:match("^%s*(%d+)%s*$")
	return id and tonumber(id) or nil
end

local function normalizeClass(kind,value)
	if value==nil or value=="" or value=="auto" then return Media.classes[kind][1] end
	local lowered=string.lower(tostring(value))
	for _,class in ipairs(Media.classes[kind]) do
		if string.lower(class)==lowered then return class end
	end
	if kind=="video" and lowered=="videodisplay" then return "VideoPlayer" end
	error("Classe '"..tostring(value).."' invalida para "..kind..": use "..table.concat(Media.classes[kind]," ou ")..".",0)
end

 
function Media.property(instance)
	if instance:IsA("Sound") then return "SoundId","string" end
	if instance:IsA("AudioPlayer") then return "Asset","string" end
	if instance:IsA("VideoFrame") then return "Video","string" end
	if instance:IsA("VideoPlayer") then return "VideoContent","content" end
	return nil
end

function Media.setAsset(instance,assetId)
	local property,kind=Media.property(instance)
	assert(property,instance.ClassName.." nao recebe audio/video (use Sound, AudioPlayer, VideoFrame ou VideoPlayer).")
	if kind=="content" then
		instance[property]=Content.fromAssetId(assetId)
	else
		instance[property]=assetUri(assetId)
	end
end

local function faceEnum(value)
	if typeof(value)=="EnumItem" then return value end
	local name=tostring(value or "Front")
	local ok,face=pcall(function() return Enum.NormalId[name] end)
	return ok and face or Enum.NormalId.Front
end

local function screenFor(parent,name,target)
	if parent:IsA("BasePart") then
		local gui=Instance.new("SurfaceGui")
		gui.Name=name.."Screen"
		gui.Face=faceEnum(target.face)
		gui.SizingMode=Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud=tonumber(target.pixelsPerStud) or 50
		gui.LightInfluence=0
		gui.AlwaysOnTop=target.alwaysOnTop==true
		gui.Parent=parent
		return gui,true
	end
	return Resolve.guiParent(parent),false
end

local function wire(source,target,name)
	local w=Instance.new("Wire")
	w.Name=name or "Wire"
	w.SourceInstance=source
	w.TargetInstance=target
	w.Parent=source
	return w
end

local function audioOutput(player,parent,options)
	local output=string.lower(tostring(options.output or "auto"))
	local emitterHost=parent:IsA("BasePart") or parent:IsA("Attachment")
	if output=="none" then return nil end
	if output=="emitter" or (output=="auto" and emitterHost) then
		assert(emitterHost,"output='emitter' exige um BasePart ou Attachment como parent.")
		local emitter=Instance.new("AudioEmitter")
		emitter.Name=player.Name.."Emitter"
		emitter.Parent=parent
		wire(player,emitter,"EmitterWire")
		return emitter
	end
	local device=Instance.new("AudioDeviceOutput")
	device.Name="Output"
	device.Parent=player
	wire(player,device,"OutputWire")
	return device
end

local function build(kind,class,name,parent,target,options,assetId)
	local root,extras={},nil
	if class=="Sound" then
		local sound=Instance.new("Sound")
		sound.Name=name
		sound.Looped=options.looped==true or options.loop==true
		sound.Volume=tonumber(options.volume) or 0.5
		if options.playbackSpeed then sound.PlaybackSpeed=tonumber(options.playbackSpeed) or 1 end
		if options.rollOffMaxDistance then sound.RollOffMaxDistance=tonumber(options.rollOffMaxDistance) or 10000 end
		if assetId then sound.SoundId=assetUri(assetId) end
		sound.Playing=options.playing==true or options.autoplay==true
		sound.Parent=parent
		root=sound
	elseif class=="AudioPlayer" then
		local player=create("AudioPlayer")
		player.Name=name
		player.Looping=options.looped==true or options.loop==true
		player.Volume=tonumber(options.volume) or 0.5
		player.AutoLoad=true
		if assetId then player.Asset=assetUri(assetId) end
		 
		extras={output=audioOutput(player,parent,options)}
		player.Parent=parent
		if options.playing==true or options.autoplay==true then
			pcall(function() player:Play() end)
		end
		root=player
	elseif class=="VideoFrame" then
		local gui,onPart=screenFor(parent,name,target)
		local frame=Instance.new("VideoFrame")
		frame.Name=name
		frame.BackgroundTransparency=1
		frame.Looped=options.looped~=false and options.loop~=false
		frame.Volume=tonumber(options.volume) or 1
		if onPart then
			frame.Size=UDim2.fromScale(1,1)
		else
			frame.Size=UDim2.fromOffset(tonumber(options.width) or 480,tonumber(options.height) or 270)
			frame.Position=UDim2.fromScale(0.5,0.5)
			frame.AnchorPoint=Vector2.new(0.5,0.5)
		end
		if assetId then frame.Video=assetUri(assetId) end
		frame.Playing=options.playing~=false and options.autoplay~=false
		frame.Parent=gui
		root=frame
		extras={gui=onPart and gui or nil}
	else
		 
		local player=create("VideoPlayer",NEW_VIDEO_HINT)
		local display=create("VideoDisplay",NEW_VIDEO_HINT)
		player.Name=name
		player.Looping=options.looped~=false and options.loop~=false
		player.Volume=tonumber(options.volume) or 1
		pcall(function() player.AutoLoadInStudio=true end)
		if assetId then player.VideoContent=Content.fromAssetId(assetId) end
		local output=audioOutput(player,parent,options)
		local gui,onPart=screenFor(parent,name,target)
		display.Name=name.."Display"
		display.BackgroundTransparency=1
		display.Size=onPart and UDim2.fromScale(1,1) or UDim2.fromOffset(tonumber(options.width) or 480,tonumber(options.height) or 270)
		if not onPart then
			display.Position=UDim2.fromScale(0.5,0.5)
			display.AnchorPoint=Vector2.new(0.5,0.5)
		end
		display.Parent=gui
		player.Parent=parent:IsA("BasePart") and parent or gui
		wire(player,display,"VideoWire")
		root=player
		extras={gui=onPart and gui or nil,display=display,output=output}
	end
	return root,extras
end

local function stash(root,kind,bytes,info,yield)
	local package=root:FindFirstChild(Limits.PACKAGE)
	if package then package:Destroy() end
	package=Instance.new("Folder")
	package.Name=Limits.PACKAGE
	package:SetAttribute("Version",Limits.VERSION)
	package:SetAttribute("Kind",KIND_NAMES[kind])
	Store.write(package,bytes,FORMATS[kind],yield)
	local readme=Instance.new("StringValue")
	readme.Name="LEIA_ME"
	readme.Value="ImportMCP: arquivo original de "..kind.." aguardando upload. Use Api.media.upload(path) com uma chave Open Cloud, ou envie pelo Creator Hub e chame Api.media.bind(path, assetId). Esta pasta e removida ao concluir."
	readme.Parent=package
	package.Parent=root
	root:SetAttribute("ImportMCP_Bytes",buffer.len(bytes))
	if info.fileName then root:SetAttribute("ImportMCP_FileName",tostring(info.fileName):sub(1,120)) end
	if info.format then root:SetAttribute("ImportMCP_Format",tostring(info.format)) end
	return package
end

local function describeInfo(info)
	if not info then return {} end
	local out={Format=info.format,Duration=info.duration,SampleRate=info.sampleRate,Channels=info.channels,Width=info.width,Height=info.height,Bitrate=info.bitrate,Source=info.fileName}
	return out
end

local function markPending(root,kind,reason,info,operationId)
	for name in pairs(root:GetAttributes()) do
		if name:sub(1,10)=="ImportMCP_" then root:SetAttribute(name,nil) end
	end
	root:SetAttribute("ImportMCP_Kind",KIND_NAMES[kind])
	root:SetAttribute("ImportMCP_Mode","pending")
	root:SetAttribute("ImportMCP_Version",Limits.VERSION)
	root:SetAttribute("ImportMCP_Status","PendingUpload")
	root:SetAttribute("ImportMCP_PendingReason",tostring(reason):sub(1,900))
	 
	if operationId then root:SetAttribute("ImportMCP_Operation",tostring(operationId)) end
	for key,value in pairs(describeInfo(info)) do
		if value~=nil and type(value)~="table" then root:SetAttribute("ImportMCP_"..key,value) end
	end
	CollectionService:AddTag(root,Limits.TAG)
end

local function markAsset(root,kind,assetId,info,extra)
	local attributes=describeInfo(info)
	for key,value in pairs(extra or {}) do attributes[key]=value end
	Materialize.mark(root,KIND_NAMES[kind],{assetId},attributes)
	root:SetAttribute("ImportMCP_AssetId",assetId)
	local package=root:FindFirstChild(Limits.PACKAGE)
	if package then package:Destroy() end
end

local function tryUpload(bytes,info,job,options,ctx)
	local cloud=type(options.openCloud)=="table" and options.openCloud or {}
	local apiKey=OpenCloud.apiKey(cloud.apiKey or options.apiKey)
	if not apiKey then return nil,"Sem chave Open Cloud configurada (Api.setOpenCloud{apiKey=...} ou openCloud={apiKey=...}).","nokey" end
	local ok,result=pcall(OpenCloud.upload,bytes,{kind=info.kind,name=job.name,description=options.description,fileName=info.fileName or (job.name.."."..(info.ext or "bin")),mime=info.mime,ext=info.ext,apiKey=apiKey,creator=cloud.creator or options.creator,check=ctx.check,stage=ctx.stage,timeout=options.timeout})
	if ok then return result end
	return nil,OpenCloud.errorText(result),OpenCloud.errorCode(result) or "failed",type(result)=="table" and result.operationId or nil
end

 
function Media.import(job,ctx)
	ctx=ctx or {}
	local yield=ctx.yield or Yield.ticker(ctx.check)
	local target=job.target or {}
	local options=job.options or {}
	local assetId=Media.parseAssetId(options.assetId or job.assetId or target.assetId)
	local info,probeError
	if typeof(job.bytes)=="buffer" then
		if ctx.stage then ctx.stage("analisando") end
		info,probeError=Probe.inspect(job.bytes,job.fileName)
		assert(info,"Arquivo nao reconhecido como audio/video ("..tostring(probeError).."). Formatos: MP3, OGG, WAV, FLAC, MP4, MOV.")
		if job.kind and job.kind~="auto" and job.kind~=info.kind then
			error("O arquivo e um "..info.kind.." ("..tostring(info.format).."), nao "..tostring(job.kind)..".",0)
		end
		local problems=Probe.problems(info)
		if #problems>0 and options.force~=true then error(table.concat(problems," "),0) end
	else
		assert(assetId,"Informe os bytes da midia (url/data/upload) ou um assetId ja publicado.")
		local kind=job.kind~="auto" and job.kind or Probe.kindFromName(job.fileName)
		assert(kind=="audio" or kind=="video","Com assetId informe kind='audio' ou 'video'.")
		info={kind=kind,fileName=job.fileName}
	end
	local kind=info.kind
	local class=normalizeClass(kind,target.class or options.class)
	local upload,pendingReason,pendingCode,pendingOperation
	if not assetId and job.bytes and options.upload~=false then
		upload,pendingReason,pendingCode,pendingOperation=tryUpload(job.bytes,info,job,options,ctx)
		if upload then assetId=upload.assetId end
		if not assetId and options.pending==false then error(pendingReason,0) end
	elseif not assetId then
		pendingReason="Upload desativado (options.upload=false)."
		pendingCode="disabled"
	end
	if ctx.stage then ctx.stage("construindo") end
	local root,extras
	if target.applyTo then
		root=Resolve.instance(target.applyTo,false)
		assert(Media.property(root),root.ClassName.." nao recebe "..kind.."; use Sound, AudioPlayer, VideoFrame ou VideoPlayer.")
		if assetId then Media.setAsset(root,assetId) end
		extras={}
	else
		local defaultParent=kind=="audio" and SoundService or workspace
		local parent=Resolve.parent(target.parent,defaultParent)
		local name=Resolve.uniqueName(parent,job.name)
		root,extras=build(kind,class,name,parent,target,options,assetId)
	end
	local applied,failed=Props.apply(root,target.properties)
	local stashed=false
	if assetId then
		markAsset(root,kind,assetId,info,{Operation=upload and upload.operationId or nil})
	else
		markPending(root,kind,pendingReason,info,pendingOperation)
		if job.bytes and options.stash~=false and buffer.len(job.bytes)<=Limits.MAX_BYTES then
			if ctx.stage then ctx.stage("persistindo") end
			stash(root,kind,job.bytes,info,yield)
			stashed=true
		end
	end
	local notes={}
	if not assetId and pendingCode=="processing" then
		notes[#notes+1]="Upload aceito pela Roblox e ainda em processamento (operacao "..tostring(pendingOperation).."); rode Api.media.upload('"..root:GetFullName().."') em instantes para vincular o asset sem reenviar o arquivo."
	elseif not assetId then
		notes[#notes+1]="Midia inserida sem asset ("..tostring(pendingReason)..")."
		if stashed then notes[#notes+1]="O arquivo original ficou em "..root:GetFullName().."."..Limits.PACKAGE.."; conclua com Api.media.upload('"..root:GetFullName().."') apos Api.setOpenCloud{apiKey=...}, ou publique pelo Creator Hub (Asset Manager > Import) e chame Api.media.bind('"..root:GetFullName().."', assetId)." end
	elseif upload then
		notes[#notes+1]="Asset "..assetId.." criado via Open Cloud; audios/videos enviados assim sao privados do criador e podem levar alguns segundos ate tocar no Studio."
	end
	if kind=="video" and class=="VideoPlayer" then notes[#notes+1]="VideoPlayer/VideoDisplay exigem o beta 'New Video API' no Studio; use class='VideoFrame' para o caminho classico." end
	if kind=="audio" and class=="AudioPlayer" then notes[#notes+1]="AudioPlayer usa a Audio API nova: o som sai pelo "..(extras and extras.output and extras.output.ClassName or "Wire").." criado ao lado." end
	return root,{
		kind=kind,class=root.ClassName,assetId=assetId,assetUri=assetId and assetUri(assetId) or nil,pending=assetId==nil,pendingReason=pendingReason,pendingCode=pendingCode,stashed=stashed,
		operationId=upload and upload.operationId or pendingOperation,uploaded=upload~=nil,
		media={format=info.format,duration=info.duration,sampleRate=info.sampleRate,channels=info.channels,width=info.width,height=info.height,bitrate=info.bitrate,codec=info.codec,bytes=info.bytes},
		notes=notes,propertiesApplied=applied,propertiesFailed=failed,persisted=assetId~=nil or stashed,mode=assetId and "asset" or "pending",
		screen=extras and extras.gui and extras.gui:GetFullName() or nil,display=extras and extras.display and extras.display:GetFullName() or nil,output=extras and extras.output and extras.output:GetFullName() or nil,
	}
end

function Media.isPending(instance)
	return typeof(instance)=="Instance" and instance:GetAttribute("ImportMCP_Status")=="PendingUpload"
end

function Media.kindOf(instance)
	local kind=instance:GetAttribute("ImportMCP_Kind")
	if kind=="Audio" then return "audio" end
	if kind=="Video" then return "video" end
	local property=Media.property(instance)
	if property=="SoundId" or property=="Asset" then return "audio" end
	if property then return "video" end
	return nil
end

function Media.pending()
	local out={}
	for _,instance in ipairs(CollectionService:GetTagged(Limits.TAG)) do
		if Media.isPending(instance) and instance:IsDescendantOf(game) then
			out[#out+1]={path=instance:GetFullName(),class=instance.ClassName,kind=Media.kindOf(instance),reason=instance:GetAttribute("ImportMCP_PendingReason"),bytes=instance:GetAttribute("ImportMCP_Bytes"),fileName=instance:GetAttribute("ImportMCP_FileName"),format=instance:GetAttribute("ImportMCP_Format"),hasFile=instance:FindFirstChild(Limits.PACKAGE)~=nil}
		end
	end
	table.sort(out,function(a,b) return a.path<b.path end)
	return out
end

 
function Media.bind(instance,assetId)
	assetId=Media.parseAssetId(assetId)
	assert(assetId,"assetId invalido.")
	local kind=Media.kindOf(instance)
	assert(kind,instance.ClassName.." nao e uma instancia de midia.")
	Media.setAsset(instance,assetId)
	local info={fileName=instance:GetAttribute("ImportMCP_FileName"),format=instance:GetAttribute("ImportMCP_Format"),duration=instance:GetAttribute("ImportMCP_Duration")}
	markAsset(instance,kind,assetId,info)
	return {ok=true,path=instance:GetFullName(),assetId=assetId,assetUri=assetUri(assetId),kind=kind}
end

 
function Media.upload(instance,options,ctx)
	options=options or {}
	ctx=ctx or {}
	local yield=ctx.yield or Yield.ticker(ctx.check)
	local kind=Media.kindOf(instance)
	assert(kind,instance.ClassName.." nao e uma instancia de midia.")
	local fileName=instance:GetAttribute("ImportMCP_FileName")
	local previous=instance:GetAttribute("ImportMCP_Operation")
	if previous then
		local cloud=type(options.openCloud)=="table" and options.openCloud or {}
		local okState,state=pcall(OpenCloud.operation,previous,cloud.apiKey or options.apiKey)
		if okState and state.ok and state.done and state.assetId then
			Media.setAsset(instance,state.assetId)
			markAsset(instance,kind,state.assetId,{fileName=fileName,format=instance:GetAttribute("ImportMCP_Format"),duration=instance:GetAttribute("ImportMCP_Duration")},{Operation=previous})
			return {ok=true,path=instance:GetFullName(),assetId=state.assetId,assetUri=assetUri(state.assetId),operationId=previous,kind=kind,resumed=true}
		end
		if okState and state.ok and not state.done then
			return {ok=false,path=instance:GetFullName(),error="A Roblox ainda esta processando o upload (operacao "..previous.."); tente de novo em instantes.",code="processing",operationId=previous}
		end
		 
	end
	local package=instance:FindFirstChild(Limits.PACKAGE)
	assert(package,"Esta midia nao guarda o arquivo original; envie pelo Creator Hub e use Api.media.bind(path, assetId).")
	local bytes=Store.read(package,FORMATS[kind],yield)
	local info=Probe.inspect(bytes,fileName)
	assert(info and info.kind==kind,"Arquivo guardado nao corresponde a um "..kind..".")
	local job={name=options.name or instance.Name,fileName=fileName or (instance.Name.."."..(info.ext or "bin"))}
	local upload,reason,code,operation=tryUpload(bytes,info,job,options,ctx)
	if not upload then
		instance:SetAttribute("ImportMCP_PendingReason",tostring(reason):sub(1,900))
		instance:SetAttribute("ImportMCP_Operation",operation)
		return {ok=false,path=instance:GetFullName(),error=reason,code=code,operationId=operation}
	end
	Media.setAsset(instance,upload.assetId)
	markAsset(instance,kind,upload.assetId,info,{Operation=upload.operationId})
	return {ok=true,path=instance:GetFullName(),assetId=upload.assetId,assetUri=assetUri(upload.assetId),operationId=upload.operationId,kind=kind}
end

return table.freeze(Media)
