local RunService=game:GetService("RunService")
if not RunService:IsRunning() or not RunService:IsServer() then return end
if script.Parent==nil or not script.Parent:IsDescendantOf(game:GetService("ServerScriptService")) then return end

local Loader=require(script.Parent.Loader)
local Limits=require(script.Parent.Limits)

Loader.watch()

local lastReport
for attempt=1,Limits.RESTORE_ATTEMPTS do
	local ok,report=pcall(Loader.restoreAll,{})
	if ok then
		lastReport=report
		if report.failed==0 then break end
	else
		lastReport={restored=0,failed=1,errors={tostring(report)}}
	end
	task.wait(2^(attempt-1))
end

if lastReport and lastReport.failed>0 then
	warn("ImportMCP: "..lastReport.failed.." asset(s) nao restaurado(s). Confira se Mesh/Image APIs estao habilitadas na experiencia. "..table.concat(lastReport.errors," | "))
end
