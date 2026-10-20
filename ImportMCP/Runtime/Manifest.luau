local Limits=require(script.Parent.Limits)
local CollectionService=game:GetService("CollectionService")
local HttpService=game:GetService("HttpService")

local Manifest={TAG=Limits.TAG,PACKAGE=Limits.PACKAGE}

Manifest.ATTR=table.freeze({
	Kind="ImportMCP_Kind",
	Format="ImportMCP_Format",
	Version="ImportMCP_Version",
	Status="ImportMCP_Status",
	Error="ImportMCP_LastError",
	Options="ImportMCP_Options",
	Source="ImportMCP_Source",
	Bytes="ImportMCP_Bytes",
	Hash="ImportMCP_Hash",
	Part="ImportMCP_Part",
	Parts="ImportMCP_Parts",
	Property="ImportMCP_Property",
	Imported="ImportMCP_ImportedAt",
})

local ATTR=Manifest.ATTR

function Manifest.package(instance)
	local package=instance:FindFirstChild(Manifest.PACKAGE)
	if package and package:IsA("Folder") then return package end
	return nil
end

function Manifest.ensurePackage(instance)
	local package=Manifest.package(instance)
	if package then return package end
	package=Instance.new("Folder")
	package.Name=Manifest.PACKAGE
	package:SetAttribute("Version",Limits.VERSION)
	package.Parent=instance
	return package
end

function Manifest.isAsset(instance)
	return typeof(instance)=="Instance" and instance:GetAttribute(ATTR.Kind)~=nil and Manifest.package(instance)~=nil
end

function Manifest.write(instance,meta)
	assert(type(meta)=="table" and (meta.kind=="image" or meta.kind=="model"),"Meta de asset invalida.")
	instance:SetAttribute(ATTR.Kind,meta.kind)
	instance:SetAttribute(ATTR.Format,tostring(meta.format or ""))
	instance:SetAttribute(ATTR.Version,Limits.VERSION)
	instance:SetAttribute(ATTR.Source,tostring(meta.name or ""))
	instance:SetAttribute(ATTR.Bytes,meta.bytes or 0)
	instance:SetAttribute(ATTR.Hash,tostring(meta.hash or ""))
	instance:SetAttribute(ATTR.Options,HttpService:JSONEncode(meta.options or {}))
	instance:SetAttribute(ATTR.Imported,os.time())
	if meta.parts then instance:SetAttribute(ATTR.Parts,meta.parts) end
	if meta.property then instance:SetAttribute(ATTR.Property,meta.property) end
	instance:SetAttribute(ATTR.Status,"Ready")
	instance:SetAttribute(ATTR.Error,nil)
	CollectionService:AddTag(instance,Manifest.TAG)
end

function Manifest.read(instance)
	local kind=instance:GetAttribute(ATTR.Kind)
	assert(kind=="image" or kind=="model","A instancia nao e um asset ImportMCP.")
	local encoded=instance:GetAttribute(ATTR.Options)
	local options={}
	if type(encoded)=="string" and #encoded>0 then
		local ok,decoded=pcall(HttpService.JSONDecode,HttpService,encoded)
		if ok and type(decoded)=="table" then options=decoded end
	end
	return {
		kind=kind,
		format=instance:GetAttribute(ATTR.Format),
		version=instance:GetAttribute(ATTR.Version) or 1,
		name=instance:GetAttribute(ATTR.Source) or instance.Name,
		bytes=instance:GetAttribute(ATTR.Bytes) or 0,
		hash=instance:GetAttribute(ATTR.Hash) or "",
		parts=instance:GetAttribute(ATTR.Parts),
		property=instance:GetAttribute(ATTR.Property),
		options=options,
	}
end

function Manifest.status(instance,status,err)
	instance:SetAttribute(ATTR.Status,status)
	if err~=nil then
		instance:SetAttribute(ATTR.Error,string.sub(tostring(err),1,900))
	else
		instance:SetAttribute(ATTR.Error,nil)
	end
end

function Manifest.parts(instance)
	if instance:IsA("MeshPart") and instance:GetAttribute(ATTR.Part)~=nil then
		return {instance}
	end
	local parts={}
	for _,child in ipairs(instance:GetChildren()) do
		if child:IsA("MeshPart") and child:GetAttribute(ATTR.Part)~=nil then
			parts[#parts+1]=child
		end
	end
	table.sort(parts,function(a,b)
		return (a:GetAttribute(ATTR.Part) or 0)<(b:GetAttribute(ATTR.Part) or 0)
	end)
	return parts
end

function Manifest.describe(instance)
	local meta=Manifest.read(instance)
	return {
		path=instance:GetFullName(),
		class=instance.ClassName,
		name=instance.Name,
		kind=meta.kind,
		format=meta.format,
		source=meta.name,
		bytes=meta.bytes,
		hash=meta.hash,
		parts=meta.parts,
		status=instance:GetAttribute(ATTR.Status),
		error=instance:GetAttribute(ATTR.Error),
	}
end

return table.freeze(Manifest)
