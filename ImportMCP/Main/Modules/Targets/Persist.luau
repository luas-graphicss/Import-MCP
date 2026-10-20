local Runtime=script.Parent.Parent.Runtime
local Limits=require(Runtime.Limits)
local Store=require(Runtime.Store)
local Loader=require(Runtime.Loader)
local Materialize=require(Runtime.Materialize)
local Yield=require(Runtime.Yield)
local LiveToken=require(Runtime.LiveToken)
local CollectionService=game:GetService("CollectionService")
local ReplicatedStorage=game:GetService("ReplicatedStorage")

local Persist={}

local README="ImportMCP: mantenha esta pasta e o script "..Limits.LOADER.." junto do asset. O Payload e a fonte persistente; o conteudo visual (MeshContent/TextureContent/ImageContent) e recriado em cada servidor/cliente a partir dele usando ReplicatedStorage."..Limits.RUNTIME_NAME..". Nao e necessario publicar assets nem usar o importador do Studio. Habilite Mesh/Image APIs nas configuracoes da experiencia."

function Persist.runtimeStatus()
	local installed=ReplicatedStorage:FindFirstChild(Limits.RUNTIME_NAME)
	local version=installed and installed:GetAttribute("Version") or nil
	return {installed=installed~=nil,version=version,expected=Limits.VERSION,upToDate=version==Limits.VERSION,path=installed and installed:GetFullName() or nil}
end

function Persist.installRuntime(force)
	local status=Persist.runtimeStatus()
	if status.installed and status.upToDate and not force then return ReplicatedStorage[Limits.RUNTIME_NAME],false end
	local existing=ReplicatedStorage:FindFirstChild(Limits.RUNTIME_NAME)
	local clone=Runtime:Clone()
	clone.Name=Limits.RUNTIME_NAME
	clone:SetAttribute("Version",Limits.VERSION)
	for _,child in ipairs(clone:GetChildren()) do
		if child:IsA("BaseScript") then child.Disabled=true end
	end
	if existing then existing:Destroy() end
	clone.Parent=ReplicatedStorage
	return clone,true
end

local function loaderTemplate(kind)
	local template=Runtime:FindFirstChild(kind=="Mesh" and "ServerLoader" or "ClientLoader")
	assert(template and template:IsA("Script"),"Template de carregador ausente no Runtime.")
	return template
end

function Persist.detach(root)
	local package=root:FindFirstChild(Limits.PACKAGE)
	if package then package:Destroy() end
	local loader=root:FindFirstChild(Limits.LOADER)
	if loader then loader:Destroy() end
	for name in pairs(root:GetAttributes()) do
		if name:sub(1,10)=="ImportMCP_" then root:SetAttribute(name,nil) end
	end
	CollectionService:RemoveTag(root,Limits.TAG)
end

function Persist.attach(root,kind,data,format,info,yield)
	assert(typeof(root)=="Instance","Instancia alvo invalida.")
	assert(kind=="Mesh" or kind=="Image","Tipo de asset invalido.")
	yield=yield or Yield.ticker()
	Persist.installRuntime(false)
	local package=root:FindFirstChild(Limits.PACKAGE)
	if package then package:Destroy() end
	local loader=root:FindFirstChild(Limits.LOADER)
	if loader then loader:Destroy() end
	package=Instance.new("Folder")
	package.Name=Limits.PACKAGE
	package:SetAttribute("Version",Limits.VERSION)
	package:SetAttribute("Kind",kind)
	Store.write(package,data,format,yield)
	local readme=Instance.new("StringValue")
	readme.Name="LEIA_ME"
	readme.Value=README
	readme.Parent=package
	package.Parent=root
	loader=loaderTemplate(kind):Clone()
	loader.Name=Limits.LOADER
	loader.RunContext=kind=="Mesh" and Enum.RunContext.Server or Enum.RunContext.Client
	loader.Disabled=false
	loader.Parent=root
	root:SetAttribute("ImportMCP_Kind",kind)
	root:SetAttribute("ImportMCP_Format",format)
	root:SetAttribute("ImportMCP_Version",Limits.VERSION)
	root:SetAttribute("ImportMCP_Bytes",buffer.len(data))
	root:SetAttribute("ImportMCP_Status","Ready")
	root:SetAttribute("ImportMCP_LastError",nil)
	if type(info)=="table" then
		for key,value in pairs(info) do
			if value~=nil and type(value)~="table" then root:SetAttribute("ImportMCP_"..key,value) end
		end
	end
	CollectionService:AddTag(root,Limits.TAG)
	 
	LiveToken.stamp(root)
	return package
end

function Persist.restore(root,options)
	return Loader.restore(root,options)
end

function Persist.tagged()
	local out={}
	for _,instance in ipairs(CollectionService:GetTagged(Limits.TAG)) do
		if Loader.kind(instance) and instance:IsDescendantOf(game) then out[#out+1]=instance end
	end
	table.sort(out,function(a,b) return a:GetFullName()<b:GetFullName() end)
	return out
end

 
function Persist.permanent()
	local out={}
	for _,instance in ipairs(CollectionService:GetTagged(Limits.TAG)) do
		if Materialize.isPermanent(instance) and instance:IsDescendantOf(game) then out[#out+1]=instance end
	end
	table.sort(out,function(a,b) return a:GetFullName()<b:GetFullName() end)
	return out
end

function Persist.describe(instance)
	local permanent=Materialize.isPermanent(instance)
	return {path=instance:GetFullName(),class=instance.ClassName,kind=instance:GetAttribute("ImportMCP_Kind"),mode=permanent and "asset" or "session",status=instance:GetAttribute("ImportMCP_Status"),bytes=instance:GetAttribute("ImportMCP_Bytes"),error=instance:GetAttribute("ImportMCP_LastError"),chunks=instance:GetAttribute("ImportMCP_Chunks"),width=instance:GetAttribute("ImportMCP_Width"),height=instance:GetAttribute("ImportMCP_Height"),assetIds=permanent and Materialize.assetIds(instance) or nil,live=not permanent and Loader.materialized(instance) or nil}
end

 
function Persist.liveSummary()
	local materialized,missing,paths=0,0,{}
	for _,instance in ipairs(Persist.tagged()) do
		if Loader.materialized(instance) then
			materialized+=1
		else
			missing+=1
			if #paths<20 then paths[#paths+1]=instance:GetFullName() end
		end
	end
	return {token=LiveToken.current(false)~=nil,materialized=materialized,missing=missing,missingPaths=paths}
end

function Persist.list()
	local out={}
	for _,instance in ipairs(Persist.permanent()) do out[#out+1]=Persist.describe(instance) end
	for _,instance in ipairs(Persist.tagged()) do out[#out+1]=Persist.describe(instance) end
	return out
end

 
 
function Persist.restoreAll(options)
	options=options or {}
	local report={restored=0,failed=0,skipped=0,errors={}}
	for _,instance in ipairs(Persist.tagged()) do
		if options.shouldContinue and not options.shouldContinue() then break end
		if options.onlyMissing and Loader.materialized(instance) then
			report.skipped+=1
		else
			local ok,err=pcall(Loader.restore,instance,options)
			if ok then report.restored+=1 else
				report.failed+=1
				report.errors[#report.errors+1]=instance:GetFullName()..": "..tostring(err):match("^[^\n]+")
			end
			task.wait()
		end
	end
	return report
end

return table.freeze(Persist)
