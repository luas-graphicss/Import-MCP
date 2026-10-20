local Limits=require(script.Parent.Limits)

local Yield={}

function Yield.ticker(check,slice)
	slice=slice or Limits.SLICE
	local mark=os.clock()
	return function()
		if check then check() end
		if os.clock()-mark>=slice then
			task.wait()
			mark=os.clock()
			if check then check() end
		end
	end
end

function Yield.none()
	return function() end
end

return table.freeze(Yield)
