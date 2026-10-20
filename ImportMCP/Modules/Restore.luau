local History=require(script.Parent.History)
local Runtime=script.Parent.Parent.Runtime
local Loader=require(Runtime.Loader)
local Manifest=require(Runtime.Manifest)
local RunService=game:GetService("RunService")
local CollectionService=game:GetService("CollectionService")

local Restore={}

local function options(force)
	return {
		force=force,
		shouldContinue=function() return not RunService:IsRunning() end,
		commit=function(fn) History.record("ImportMCP: restaurar asset",fn) end,
	}
end

function Restore.asset(instance,force)
	assert(Manifest.isAsset(instance),"A instancia nao e um asset ImportMCP.")
	Loader.restore(instance,options(force))
	return Manifest.describe(instance)
end

function Restore.all(force)
	return Loader.restoreAll(options(force))
end

function Restore.pending()
	local count=0
	for _,instance in ipairs(CollectionService:GetTagged(Manifest.TAG)) do
		if Manifest.isAsset(instance) and not Loader.isRestored(instance) then count+=1 end
	end
	return count
end

function Restore.list()
	local out={}
	for _,instance in ipairs(CollectionService:GetTagged(Manifest.TAG)) do
		if Manifest.isAsset(instance) then
			local entry=Manifest.describe(instance)
			entry.restored=Loader.isRestored(instance)
			out[#out+1]=entry
		end
	end
	return out
end

return table.freeze(Restore)
