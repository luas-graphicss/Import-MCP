local Modules=script.Parent.Modules
local Config=require(Modules.Config)
local Importer=require(Modules.Importer)
local Staging=require(Modules.Staging)
local Targets=require(Modules.Targets)
local Restore=require(Modules.Restore)
local Persist=require(Modules.Persist)
local RuntimeInstall=require(Modules.RuntimeInstall)
local History=require(Modules.History)
local Runtime=script.Parent.Runtime
local Manifest=require(Runtime.Manifest)
local Apply=require(Runtime.Build.Apply)

local Api={}

local function failure(err)
	local message=tostring(err):match("^[^\n]+") or tostring(err)
	message=message:gsub("^[%w%._]+:%d+: ","")
	return {ok=false,error=message}
end

local function guard(fn)
	return function(...)
		local ok,result=pcall(fn,...)
		if not ok then return failure(result) end
		if type(result)~="table" then result={value=result} end
		if result.ok==nil then result.ok=true end
		return result
	end
end

Api.version=guard(function()
	return {
		name=Config.NAME,
		version=Config.VERSION,
		runtime=Config.RUNTIME_VERSION,
		runtimeInstalled=RuntimeInstall.version(),
	}
end)

Api.capabilities=guard(function()
	return {
		formats={"png","jpg","jpeg","glb","gltf"},
		kinds={"image","model"},
		imageClasses={"ImageLabel","ImageButton","Decal","Texture"},
		modelClasses={"Model","MeshPart"},
		applyClasses=Apply.IMAGE_CLASSES,
		maxBytes=Config.MAX_BYTES,
		maxTexture=Config.MAX_TEXTURE,
		request={
			name="string (nome do arquivo, ex.: heroi.png)",
			data="string base64 do arquivo",
			kind="auto | image | model",
			target="caminho, ex.: game.Workspace ou game.StarterGui.HUD",
			as="ImageLabel | ImageButton | Decal | Texture | Model | MeshPart | apply",
			position="{x,y,z} para 3D ou UDim2 {sx,ox,sy,oy} para GUI",
			rotation="{x,y,z} graus (3D)",
			size="{w,h} offsets ou {sx,ox,sy,oy} (GUI)",
			anchor="{x,y} (GUI)",
			face="Front|Back|Top|Bottom|Left|Right (Decal/Texture)",
			scale="numero (3D, multiplicador de unidades)",
			maxSize="16..1024 (limite de textura)",
			collision="Default|Box|Hull|PreciseConvexDecomposition",
			center="bool (3D, centraliza no pivo; padrao true)",
			ground="bool (3D, base em y=0; padrao false)",
			doubleSided="bool (3D)",
			canCollide="bool (3D)",
			props="tabela de propriedades aplicadas via pcall",
			externals="tabela nome -> base64 (.bin e imagens de um .gltf)",
			select="bool (selecionar no Explorer; padrao true)",
		},
	}
end)

Api.import=guard(function(request)
	return Importer.run(request)
end)

Api.begin=guard(function(spec)
	return {session=Staging.begin(spec)}
end)

Api.chunk=guard(function(session,index,text)
	return Staging.chunk(session,index,text)
end)

Api.external=guard(function(session,fileName,index,text)
	return Staging.external(session,fileName,index,text)
end)

Api.commit=guard(function(session,request)
	local staged=Staging.assemble(session)
	request=type(request)=="table" and table.clone(request) or {}
	request.name=request.name or staged.name
	request.kind=request.kind or staged.kind
	request.data=staged.data
	if next(staged.externals)~=nil then
		local merged=type(request.externals)=="table" and table.clone(request.externals) or {}
		for name,value in pairs(staged.externals) do merged[name]=value end
		request.externals=merged
	end
	local result=Importer.run(request)
	Staging.abort(session)
	result.session=session
	result.chunks=staged.chunks
	return result
end)

Api.abort=guard(function(session)
	return {removed=Staging.abort(session)}
end)

Api.sessions=guard(function()
	return {sessions=Staging.list()}
end)

Api.restore=guard(function(target,force)
	if target==nil then
		return Restore.all(force==true)
	end
	local instance=Targets.resolve(target)
	assert(instance,"Alvo nao encontrado.")
	return Restore.asset(instance,force==true)
end)

Api.list=guard(function()
	return {assets=Restore.list()}
end)

Api.describe=guard(function(target)
	local instance=Targets.resolve(target)
	assert(instance and Manifest.isAsset(instance),"O alvo nao e um asset ImportMCP.")
	return Manifest.describe(instance)
end)

Api.remove=guard(function(target,keepInstance)
	local instance=Targets.resolve(target)
	assert(instance and Manifest.isAsset(instance),"O alvo nao e um asset ImportMCP.")
	local path=instance:GetFullName()
	History.record("ImportMCP: remover asset",function()
		if keepInstance then
			Persist.detach(instance)
		else
			instance:Destroy()
		end
	end)
	return {removed=path,kept=keepInstance==true}
end)

Api.installRuntime=guard(function(force)
	local folder,changed=RuntimeInstall.ensure(force==true)
	return {path=folder:GetFullName(),version=folder:GetAttribute("Version"),changed=changed}
end)

Api.status=guard(function()
	return {
		name=Config.NAME,
		version=Config.VERSION,
		busy=Importer.busy(),
		runtime=RuntimeInstall.version(),
		assets=#Restore.list(),
		pendingRestore=Restore.pending(),
		sessions=#Staging.list(),
	}
end)

return table.freeze(Api)
