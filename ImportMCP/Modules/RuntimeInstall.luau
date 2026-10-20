local Config=require(script.Parent.Config)
local Limits=require(script.Parent.Parent.Runtime.Limits)
local ServerScriptService=game:GetService("ServerScriptService")

local RuntimeInstall={}

function RuntimeInstall.template()
	return script.Parent.Parent.Runtime
end

function RuntimeInstall.installed()
	local found=ServerScriptService:FindFirstChild(Limits.RUNTIME_NAME)
	if found and found:IsA("Folder") then return found end
	return nil
end

function RuntimeInstall.version()
	local current=RuntimeInstall.installed()
	return current and current:GetAttribute("Version") or nil
end

function RuntimeInstall.ensure(force)
	local current=RuntimeInstall.installed()
	if current and not force and current:GetAttribute("Version")==Config.RUNTIME_VERSION then
		return current,false
	end
	local template=RuntimeInstall.template()
	assert(template and template:FindFirstChild("Bootstrap") and template:FindFirstChild("Loader"),"Template do runtime ausente em "..script.Parent.Parent:GetFullName())
	local copy=template:Clone()
	copy.Name=Limits.RUNTIME_NAME
	copy:SetAttribute("Version",Config.RUNTIME_VERSION)
	copy:SetAttribute("InstalledBy",Config.NAME.." "..Config.VERSION)
	local bootstrap=copy:FindFirstChild("Bootstrap")
	bootstrap.Disabled=false
	bootstrap.Enabled=true
	pcall(function() bootstrap.RunContext=Enum.RunContext.Legacy end)
	if current then current:Destroy() end
	copy.Parent=ServerScriptService
	return copy,true
end

function RuntimeInstall.remove()
	local current=RuntimeInstall.installed()
	if current then current:Destroy() end
	return current~=nil
end

return table.freeze(RuntimeInstall)
