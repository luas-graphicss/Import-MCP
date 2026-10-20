local Limits=require(script.Parent.Limits)

local Ticker={}

function Ticker.new(shouldContinue,budget)
	local limit=budget or Limits.YIELD_SECONDS
	local last=os.clock()
	local function check()
		if shouldContinue then
			assert(shouldContinue(),"Operacao cancelada.")
		end
	end
	local function yield()
		check()
		if os.clock()-last>limit then
			task.wait()
			last=os.clock()
			check()
		end
	end
	local function checkpoint()
		check()
		task.wait()
		last=os.clock()
		check()
	end
	return yield,check,checkpoint
end

return table.freeze(Ticker)
