local RunService=game:GetService("RunService")
local HttpService=game:GetService("HttpService")

local LiveToken={}

LiveToken.FOLDER="ImportMCPLive"
LiveToken.ATTRIBUTE="ImportMCP_LiveToken"

function LiveToken.hosted()
	 
	return LiveSession~=nil
end

 
function LiveToken.studio()
	if LiveToken.hosted() then return true end
	local ok,edit=pcall(function() return RunService:IsStudio() and not RunService:IsRunning() end)
	return ok and edit==true
end

local function coreGui()
	local ok,service=pcall(function() return game:GetService("CoreGui") end)
	if ok then return service end
	return nil
end

function LiveToken.folder(create)
	local root=coreGui()
	if not root then return nil end
	local okFind,found=pcall(function() return root:FindFirstChild(LiveToken.FOLDER) end)
	if okFind and found then return found end
	 
	if not create or LiveToken.hosted() then return nil end
	local okCreate,created=pcall(function()
		local folder=Instance.new("Folder")
		folder.Name=LiveToken.FOLDER
		folder.Archivable=false
		folder:SetAttribute("Token",HttpService:GenerateGUID(false))
		folder.Parent=root
		return folder
	end)
	if okCreate then return created end
	return nil
end

function LiveToken.current(create)
	if not LiveToken.studio() then return nil end
	local folder=LiveToken.folder(create)
	local token=folder and folder:GetAttribute("Token")
	if type(token)=="string" then return token end
	return nil
end

function LiveToken.stamp(root)
	local token=LiveToken.current(true)
	if token then pcall(function() root:SetAttribute(LiveToken.ATTRIBUTE,token) end) end
	return token
end

function LiveToken.isLive(root)
	local token=LiveToken.current(false)
	if not token then return false end
	local ok,value=pcall(function() return root:GetAttribute(LiveToken.ATTRIBUTE) end)
	return ok and value==token
end

return table.freeze(LiveToken)
