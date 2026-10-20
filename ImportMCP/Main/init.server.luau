if not plugin then
	warn("ImportMCP: para rodar como plugin, clique com o botao direito em ImportMCP.Main e escolha 'Save as Local Plugin'. Via MCP use require(game.ServerStorage.ImportMCP.MCP).")
	return
end
local RunService=game:GetService("RunService")
if RunService:IsRunning() then return end
local Modules=script:WaitForChild("Modules")
local Api=require(Modules.Api)
local Persist=require(Modules.Targets.Persist)
local Materialize=require(Modules.Runtime.Materialize)

local OpenCloud=require(Modules.Media.OpenCloud)

local savedMode=plugin:GetSetting("ImportMCP_Mode")
Materialize.setDefault(savedMode=="session" and "session" or "asset")
local savedKey=plugin:GetSetting("ImportMCP_OpenCloudKey")
if type(savedKey)=="string" and #savedKey>=16 then
	local okKey,err=pcall(OpenCloud.configure,{apiKey=savedKey})
	if not okKey then warn("ImportMCP: chave Open Cloud salva ignorada -> "..tostring(err)) end
end

local alive=true
local context={connections={}}
function context.alive()
	return alive
end
function context.connect(signal,callback)
	local connection=signal:Connect(callback)
	context.connections[#context.connections+1]=connection
	return connection
end
function context.log(message)
	print("ImportMCP: "..tostring(message))
end

local toolbar=plugin:CreateToolbar("ImportMCP")
local button=toolbar:CreateButton("ImportMCP","Painel do ImportMCP: importar arquivos, status, imports persistidos e fila do MCP","rbxassetid://4458901886")
button.ClickableWhenViewportHidden=true
local widget=require(Modules.UI.Widget)(plugin,context)
context.connect(button.Click,function() widget.toggle() end)

context.worker=require(Modules.Worker)(context)
context.worker.start()

task.defer(function()
	local okInstall,err=pcall(Api.install)
	if not okInstall then warn("ImportMCP: runtime nao instalado -> "..tostring(err)) end
	local report=Persist.restoreAll({shouldContinue=function() return alive and not RunService:IsRunning() end})
	if report.failed>0 then warn("ImportMCP: "..report.failed.." asset(s) nao restaurados: "..table.concat(report.errors,"; ")) end
	if report.restored>0 then context.log(report.restored.." asset(s) restaurados ao abrir o Studio.") end
	if alive then widget.refresh() end
end)

 
 
local CoreGui=game:GetService("CoreGui")
local liveState=nil
local liveRepairing=false
local function onLiveState(state)
	if state==liveState then return end
	local previous=liveState
	liveState=state
	if not alive or state~="Idle" or previous==nil or previous=="Idle" or liveRepairing then return end
	liveRepairing=true
	task.delay(0.5,function()
		local ok,report=pcall(Persist.restoreAll,{onlyMissing=true,shouldContinue=function() return alive and not RunService:IsRunning() end})
		liveRepairing=false
		if not ok then warn("ImportMCP: falha ao rematerializar depois da Sessao Viva -> "..tostring(report)) return end
		if report.restored>0 then context.log(report.restored.." asset(s) rematerializados depois da Sessao Viva.") end
		if report.failed>0 then warn("ImportMCP: "..report.failed.." asset(s) nao rematerializados: "..table.concat(report.errors,"; ")) end
	end)
end
task.spawn(function()
	local watched=nil
	while alive do
		local bridge=CoreGui:FindFirstChild("LiveSessionBridge")
		if bridge~=watched then
			watched=bridge
			if bridge then
				context.connect(bridge:GetAttributeChangedSignal("State"),function()
					if watched==bridge then onLiveState(bridge:GetAttribute("State")) end
				end)
				onLiveState(bridge:GetAttribute("State"))
			end
		end
		task.wait(2)
	end
end)

task.spawn(function()
	while alive do
		task.wait(3)
		if alive and widget.gui.Enabled then pcall(widget.refresh) end
	end
end)

task.spawn(function()
	while alive do
		task.wait(0.2)
		if alive then pcall(widget.tickProgress) end
	end
end)

plugin.Unloading:Connect(function()
	alive=false
	for _,connection in ipairs(context.connections) do connection:Disconnect() end
end)
