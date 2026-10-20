local Runtime=script.Parent.Parent.Runtime
local Store=require(Runtime.Store)
local Manifest=require(Runtime.Manifest)
local Limits=require(Runtime.Limits)

local Persist={}

function Persist.attach(instance,meta,bytes,externals,yield)
	local existing=Manifest.package(instance)
	if existing then existing:Destroy() end
	local package=Manifest.ensurePackage(instance)
	local ok,err=pcall(function()
		Store.write(package,"Payload",bytes,yield)
		if type(externals)=="table" and next(externals)~=nil then
			local folder=Instance.new("Folder")
			folder.Name="Externals"
			folder.Parent=package
			for name,data in pairs(externals) do
				Store.write(folder,string.lower(tostring(name)),data,yield)
			end
		end
		local readme=Instance.new("StringValue")
		readme.Name="LEIA_ME"
		readme.Value="ImportMCP: mantenha esta pasta. Ela guarda o arquivo original ("..tostring(meta.format)..") em chunks; o runtime em ServerScriptService."..Limits.RUNTIME_NAME.." reconstroi a malha/imagem a cada servidor. Nao e necessario reimportar nem publicar assets."
		readme.Parent=package
		meta.hash=Store.hash(bytes)
		meta.bytes=buffer.len(bytes)
		Manifest.write(instance,meta)
	end)
	if not ok then
		package:Destroy()
		error(err,0)
	end
	return package
end

function Persist.detach(instance)
	local package=Manifest.package(instance)
	if package then package:Destroy() end
	for _,name in pairs(Manifest.ATTR) do instance:SetAttribute(name,nil) end
	game:GetService("CollectionService"):RemoveTag(instance,Manifest.TAG)
end

return table.freeze(Persist)
