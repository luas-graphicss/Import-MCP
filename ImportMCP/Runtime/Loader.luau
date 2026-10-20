local Limits=require(script.Parent.Limits)
local Manifest=require(script.Parent.Manifest)
local Store=require(script.Parent.Store)
local Ticker=require(script.Parent.Ticker)
local Image=require(script.Parent.Build.Image)
local Model=require(script.Parent.Build.Model)
local Apply=require(script.Parent.Build.Apply)
local CollectionService=game:GetService("CollectionService")

local Loader={}

local cache={}
local restored=setmetatable({},{__mode="k"})
local busy=setmetatable({},{__mode="k"})
local connections={}

local function payload(instance,yield)
	local package=Manifest.package(instance)
	assert(package,"Pacote "..Manifest.PACKAGE.." ausente em "..instance:GetFullName())
	local folder=package:FindFirstChild("Payload")
	assert(folder,"Payload ausente em "..instance:GetFullName())
	local bytes=Store.read(folder,yield)
	local externals={}
	local extra=package:FindFirstChild("Externals")
	if extra then
		for _,child in ipairs(extra:GetChildren()) do
			if child:IsA("Folder") then externals[string.lower(child.Name)]=Store.read(child,yield) end
		end
	end
	return bytes,externals
end

local function buildImage(instance,meta,yield,check)
	local bytes=payload(instance,yield)
	local content,image=Image.fromBytes(bytes,{maxSize=meta.options.maxSize,yield=yield,check=check})
	return {kind="image",content=content,width=image.width,height=image.height}
end

local function buildModel(instance,meta,yield,check)
	local bytes,externals=payload(instance,yield)
	local options=meta.options
	local parts,info=Model.build(bytes,{
		externals=externals,
		scale=options.scale,
		maxSize=options.maxSize,
		merge=options.merge,
		collision=options.collision,
		center=options.center,
		ground=options.ground,
		doubleSided=options.doubleSided,
		canCollide=options.canCollide,
		name=meta.name,
		yield=yield,
		check=check,
	})
	return {kind="model",parts=parts,info=info}
end

function Loader.isRestored(instance)
	return restored[instance]==true
end

function Loader.clearCache()
	for _,entry in pairs(cache) do
		if entry.parts then
			for _,part in ipairs(entry.parts) do pcall(part.Destroy,part) end
		end
	end
	table.clear(cache)
end

function Loader.restore(instance,options)
	options=options or {}
	assert(typeof(instance)=="Instance","Instancia invalida.")
	assert(Manifest.isAsset(instance),"A instancia nao e um asset ImportMCP: "..instance:GetFullName())
	assert(not busy[instance],"Este asset ja esta sendo restaurado.")
	busy[instance]=true
	local meta=Manifest.read(instance)
	local yield,check=Ticker.new(options.shouldContinue)
	local ok,err=xpcall(function()
		Manifest.status(instance,"Rebuilding")
		local key=meta.kind..":"..tostring(meta.hash)
		local entry=cache[key]
		if not entry or (entry.parts and #entry.parts>0 and entry.parts[1].Parent~=nil) then
			entry=meta.kind=="image" and buildImage(instance,meta,yield,check) or buildModel(instance,meta,yield,check)
			cache[key]=entry
		end
		check()
		local function commit()
			check()
			if entry.kind=="image" then
				local property=Apply.image(instance,entry.content)
				instance:SetAttribute(Manifest.ATTR.Property,property)
			else
				local targets=Manifest.parts(instance)
				assert(#targets>0,"Geometria original ausente; reimporte o asset.")
				assert(#targets==#entry.parts,"Contagem de partes diferente ("..#targets.." x "..#entry.parts.."); nao altere as partes geradas manualmente.")
				for i,target in ipairs(targets) do
					Apply.mesh(target,entry.parts[i])
				end
			end
			Manifest.status(instance,"Ready")
		end
		if options.commit then options.commit(commit) else commit() end
		restored[instance]=true
	end,debug.traceback)
	busy[instance]=nil
	if not ok then
		local message=tostring(err):match("^[^\n]+") or tostring(err)
		pcall(Manifest.status,instance,"Error",message)
		error(message,0)
	end
	return instance
end

function Loader.restoreAll(options)
	options=options or {}
	local report={restored=0,failed=0,skipped=0,errors={}}
	for _,instance in ipairs(CollectionService:GetTagged(Manifest.TAG)) do
		if options.shouldContinue and not options.shouldContinue() then break end
		if not Manifest.isAsset(instance) then
			report.skipped+=1
		elseif restored[instance] and not options.force then
			report.skipped+=1
		else
			local ok,err=pcall(Loader.restore,instance,options)
			if ok then
				report.restored+=1
			else
				report.failed+=1
				report.errors[#report.errors+1]=instance:GetFullName()..": "..tostring(err)
			end
			task.wait()
		end
	end
	return report
end

function Loader.watch()
	if connections.added then return end
	connections.added=CollectionService:GetInstanceAddedSignal(Manifest.TAG):Connect(function(instance)
		task.defer(function()
			if restored[instance] or busy[instance] or not Manifest.isAsset(instance) then return end
			local lastError
			for attempt=1,Limits.RESTORE_ATTEMPTS do
				local ok,err=pcall(Loader.restore,instance,{})
				if ok then return end
				lastError=err
				task.wait(2^(attempt-1))
			end
			warn("ImportMCP: falha ao restaurar "..instance:GetFullName()..": "..tostring(lastError))
		end)
	end)
end

function Loader.unwatch()
	for key,connection in pairs(connections) do
		connection:Disconnect()
		connections[key]=nil
	end
end

return table.freeze(Loader)
