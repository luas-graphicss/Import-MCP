local RunService=game:GetService("RunService")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local StarterGui=game:GetService("StarterGui")
if not RunService:IsRunning() or not RunService:IsClient() then return end
local root=script.Parent
if not root or root:IsDescendantOf(StarterGui) then return end
local runtime=ReplicatedStorage:WaitForChild("ImportMCPRuntime",30)
if not runtime then
	warn("ImportMCP: runtime ausente em ReplicatedStorage; "..root.Name.." nao foi reconstruido.")
	return
end
local lastError
for attempt=1,3 do
	if not root.Parent then return end
	local ok,err=xpcall(function()
		require(runtime.Loader).restore(root,{shouldContinue=function() return root.Parent~=nil end})
	end,debug.traceback)
	if ok then return end
	lastError=tostring(err):match("^[^\n]+") or tostring(err)
	if attempt<3 then task.wait(2^(attempt-1)) end
end
warn("ImportMCP: nao foi possivel reconstruir a imagem "..root.Name..". "..lastError)
