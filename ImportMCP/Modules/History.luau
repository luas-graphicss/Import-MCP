local RunService=game:GetService("RunService")

local History={}

local function service()
	local ok,result=pcall(game.GetService,game,"ChangeHistoryService")
	if ok then return result end
	return nil
end

function History.record(label,fn)
	local ChangeHistory=service()
	if RunService:IsRunning() or not ChangeHistory then
		return fn()
	end
	local started,recording=pcall(ChangeHistory.TryBeginRecording,ChangeHistory,label,label)
	if not started or not recording then
		return fn()
	end
	local ok,result=xpcall(fn,debug.traceback)
	pcall(ChangeHistory.FinishRecording,ChangeHistory,recording,ok and Enum.FinishRecordingOperation.Commit or Enum.FinishRecordingOperation.Cancel)
	if not ok then error(result,0) end
	return result
end

return table.freeze(History)
