local Config=require(script.Parent.Config)
local Targets=require(script.Parent.Targets)
local Insert2D=require(script.Parent.Insert2D)
local Insert3D=require(script.Parent.Insert3D)
local Persist=require(script.Parent.Persist)
local History=require(script.Parent.History)
local RuntimeInstall=require(script.Parent.RuntimeInstall)
local Runtime=script.Parent.Parent.Runtime
local Base64=require(Runtime.Base64)
local Ticker=require(Runtime.Ticker)
local Store=require(Runtime.Store)
local Manifest=require(Runtime.Manifest)
local RunService=game:GetService("RunService")

local Importer={}

local running=false

local function firstLine(value)
	return tostring(value):match("^[^\n]+") or tostring(value)
end

local function sanitizeName(raw,fallback)
	local text=tostring(raw or "")
	text=string.match(text,"([^/\\]+)$") or text
	text=string.gsub(text,"%.[%w]+$","")
	text=string.gsub(text,"^%s+",""):gsub("%s+$","")
	if text=="" then text=fallback end
	if #text>64 then text=string.sub(text,1,64) end
	return text
end

function Importer.detect(bytes,name)
	local n=buffer.len(bytes)
	assert(n>=12,"Arquivo vazio ou pequeno demais.")
	local head=buffer.readstring(bytes,0,math.min(n,64))
	if string.sub(head,1,8)=="\137PNG\r\n\26\n" then return "png" end
	if string.byte(head,1)==255 and string.byte(head,2)==216 then return "jpeg" end
	if string.sub(head,1,4)=="glTF" then return "glb" end
	local trimmed=string.gsub(string.sub(head,1,64),"^\239\187\191","")
	if string.match(trimmed,"^%s*{") then return "gltf" end
	local extension=string.lower(string.match(tostring(name or ""),"%.(%w+)$") or "")
	if extension=="png" then return "png" end
	if extension=="jpg" or extension=="jpeg" then return "jpeg" end
	if extension=="glb" then return "glb" end
	if extension=="gltf" then return "gltf" end
	error("Formato nao reconhecido. Envie PNG, JPG/JPEG, GLB ou glTF.",0)
end

function Importer.bytes(request,yield)
	if typeof(request.bytes)=="buffer" then return request.bytes end
	if type(request.bytes)=="string" then
		assert(#request.bytes>0,"Campo 'bytes' vazio.")
		return buffer.fromstring(request.bytes)
	end
	if type(request.dataUri)=="string" then
		local payload=string.match(request.dataUri,"^data:[^,]*;base64,(.*)$")
		assert(payload,"dataUri precisa estar em base64.")
		return Base64.decode(payload,Config.MAX_BYTES,yield)
	end
	if type(request.data)=="string" then
		assert(#request.data>0,"Campo 'data' vazio.")
		return Base64.decode(request.data,Config.MAX_BYTES,yield)
	end
	if typeof(request.source)=="Instance" and request.source:IsA("StringValue") then
		return Base64.decode(request.source.Value,Config.MAX_BYTES,yield)
	end
	error("Informe 'data' (base64), 'bytes' (binario), 'dataUri' ou 'source' (StringValue com base64).",0)
end

local function externalsOf(request,yield)
	local out={}
	if type(request.externals)~="table" then return out end
	for name,value in pairs(request.externals) do
		local key=string.lower(tostring(name))
		if typeof(value)=="buffer" then
			out[key]=value
		elseif type(value)=="string" then
			local ok,decoded=pcall(Base64.decode,value,Config.MAX_BYTES,yield)
			out[key]=ok and decoded or buffer.fromstring(value)
		end
	end
	return out
end

local function number(value,fallback,min,max)
	local n=tonumber(value)
	if n==nil then return fallback end
	return math.clamp(n,min,max)
end

function Importer.options(request,kind,format,yield,check)
	local applyTo=nil
	local className
	if request.as=="apply" or request.mode=="apply" then
		assert(kind=="image","O modo 'apply' so vale para imagens.")
		applyTo=Targets.resolve(request.target)
		assert(applyTo,"Informe 'target' apontando para a instancia que recebera a imagem.")
		assert(Targets.acceptsImage(applyTo),"A instancia "..applyTo.ClassName.." nao aceita imagem via Content.")
		if Manifest.isAsset(applyTo) then
			assert(Manifest.read(applyTo).kind=="image","O alvo ja e um asset 3D do ImportMCP; a textura dele vem do proprio glTF. Aplique em outra instancia ou reimporte o modelo com a textura embutida.")
		end
		className=applyTo.ClassName
	else
		className=Targets.className(kind,request.as or request.className)
	end
	return {
		name=sanitizeName(request.name,kind=="image" and "Imagem" or "Modelo"),
		className=className,
		applyTo=applyTo,
		format=format,
		maxSize=number(request.maxSize,Config.MAX_TEXTURE,16,Config.MAX_TEXTURE),
		scale=number(request.scale,1,0.0001,10000),
		collision=request.collision or "Default",
		center=request.center~=false,
		ground=request.ground==true,
		doubleSided=request.doubleSided==true,
		canCollide=request.canCollide~=false,
		position=request.position,
		rotation=request.rotation,
		size=request.size,
		anchor=request.anchor,
		zIndex=request.zIndex,
		scaleType=request.scaleType,
		face=request.face,
		studsPerTile=request.studsPerTile,
		props=request.props,
		yield=yield,
		check=check,
	}
end

local function persistedOptions(options)
	return {
		maxSize=options.maxSize,
		scale=options.scale,
		collision=options.collision,
		center=options.center,
		ground=options.ground,
		doubleSided=options.doubleSided,
		canCollide=options.canCollide,
		merge=options.className=="MeshPart",
	}
end

function Importer.run(request)
	assert(type(request)=="table","A requisicao precisa ser uma tabela.")
	if running and os.clock()-running>300 then running=false end
	assert(not running,"Ja existe uma importacao em andamento; aguarde terminar.")
	assert(not RunService:IsRunning(),"Pare o modo Play antes de importar.")
	running=os.clock()
	local started=os.clock()
	local ok,result=xpcall(function()
		local yield,check=Ticker.new()
		local bytes=Importer.bytes(request,yield)
		assert(buffer.len(bytes)<=Config.MAX_BYTES,"Arquivo acima de "..math.floor(Config.MAX_BYTES/1048576).." MiB.")
		local format=Importer.detect(bytes,request.name)
		local kind=Config.FORMATS[format]
		if request.kind and request.kind~="auto" then
			assert(request.kind==kind,"O arquivo e do tipo '"..kind.."', mas a requisicao pediu '"..tostring(request.kind).."'.")
		end
		local externals=externalsOf(request,yield)
		local options=Importer.options(request,kind,format,yield,check)
		local parent=options.applyTo and options.applyTo.Parent or Targets.parentFor(kind,options.className,Targets.resolve(request.target))
		RuntimeInstall.ensure(false)
		local outcome
		History.record("ImportMCP: importar "..options.name,function()
			if kind=="image" then
				outcome=Insert2D.import(bytes,parent,options)
			else
				outcome=Insert3D.import(bytes,externals,parent,options)
			end
			local meta={
				kind=kind,
				format=format,
				name=options.name,
				options=persistedOptions(options),
				parts=outcome.parts,
				property=outcome.property,
			}
			local ok2,err=pcall(Persist.attach,outcome.instance,meta,bytes,externals,yield)
			if not ok2 then
				if not options.applyTo then outcome.instance:Destroy() end
				error(err,0)
			end
		end)
		if request.select~=false then
			pcall(function() game:GetService("Selection"):Set({outcome.instance}) end)
		end
		local instance=outcome.instance
		return {
			ok=true,
			kind=kind,
			format=format,
			name=instance.Name,
			class=instance.ClassName,
			path=instance:GetFullName(),
			parent=parent:GetFullName(),
			bytes=buffer.len(bytes),
			hash=Store.hash(bytes),
			property=outcome.property,
			width=outcome.width,
			height=outcome.height,
			parts=outcome.parts,
			meshes=outcome.meshes,
			triangles=outcome.triangles,
			textures=outcome.textures,
			warnings=outcome.warnings,
			seconds=math.floor((os.clock()-started)*1000)/1000,
		}
	end,debug.traceback)
	running=false
	if not ok then error(firstLine(result),0) end
	return result
end

function Importer.busy()
	return running~=false
end

return table.freeze(Importer)
