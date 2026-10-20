local RunService=game:GetService("RunService")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
if not RunService:IsRunning() or not RunService:IsServer() then return end
local root=script.Parent
if not root or not (root:IsA("Model") or root:IsA("BasePart")) then return end
while not root:IsDescendantOf(workspace) do
	root.AncestryChanged:Wait()
	if not root.Parent then return end
end
local runtime=ReplicatedStorage:WaitForChild("ImportMCPRuntime",30)
if not runtime then
	root:SetAttribute("ImportMCP_Status","Error")
	root:SetAttribute("ImportMCP_LastError","ReplicatedStorage.ImportMCPRuntime ausente.")
	warn("ImportMCP: runtime ausente em ReplicatedStorage; "..root.Name.." nao foi reconstruido.")
	return
end
local lastError
for attempt=1,3 do
	if not root:IsDescendantOf(workspace) then return end
	local ok,err=xpcall(function()
		require(runtime.Loader).restore(root,{shouldContinue=function() return root:IsDescendantOf(workspace) end})
	end,debug.traceback)
	if ok then return end
	lastError=tostring(err):match("^[^\n]+") or tostring(err)
	if attempt<3 then task.wait(2^(attempt-1)) end
end
root:SetAttribute("ImportMCP_Status","Error")
root:SetAttribute("ImportMCP_LastError",lastError:sub(1,900))
warn("ImportMCP: nao foi possivel reconstruir "..root.Name..". Confira Mesh/Image APIs nas configuracoes da experiencia. "..lastError)
