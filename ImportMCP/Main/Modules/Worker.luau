local Modules=script.Parent
local Api=require(Modules.Api)
local Inbox=require(Modules.Transport.Inbox)
local Progress=require(Modules.Progress)
local HttpService=game:GetService("HttpService")
local RunService=game:GetService("RunService")

local MEDIA_EXTENSIONS={mp3="audio",ogg="audio",wav="audio",flac="audio",mp4="video",mov="video"}

return function(context)
	local Worker={busy=false,processed=0,failed=0,batchDone=0,batchTotal=0,lastMessage="",current=nil}
	local alive=context.alive or function() return true end
	local log=context.log or function() end
	local pending={}

	local function decodeRequest(job)
		local raw=job:GetAttribute("Request")
		local ok,decoded=pcall(HttpService.JSONDecode,HttpService,tostring(raw or ""))
		assert(ok and type(decoded)=="table","Requisicao do job ilegivel.")
		return decoded
	end

	local function stripData(job)
		local data=job:FindFirstChild("Data")
		if data then data:ClearAllChildren() end
	end

	function Worker.enqueue(spec)
		assert(typeof(spec.bytes)=="buffer" and buffer.len(spec.bytes)>0,"Arquivo vazio: "..tostring(spec.name))
		local id=Inbox.begin(Inbox.newId("file"),{name=spec.name})
		pending[id]={bytes=spec.bytes,name=spec.name,fileName=spec.name,externals=spec.externals,target=spec.target,options=spec.options,kind=spec.kind}
		Inbox.setState(id,"queued",{Local=true,Bytes=buffer.len(spec.bytes),Queued=os.time(),Request={name=spec.name,source="file",bytes=buffer.len(spec.bytes)}})
		return id
	end

	function Worker.enqueueFiles(files,defaults)
		defaults=defaults or {}
		local entries,externals={},{}
		local hasGltf=false
		for _,file in ipairs(files) do
			local name=file.Name
			local lowered=string.lower(name)
			local extension=lowered:match("%.(%w+)$") or ""
			local bytes=buffer.fromstring(file:GetBinaryContents())
			if extension=="bin" then
				externals[#externals+1]={bytes=bytes,name=lowered}
			elseif extension=="gltf" or extension=="glb" then
				hasGltf=hasGltf or extension=="gltf"
				entries[#entries+1]={bytes=bytes,name=name,mesh=true}
			elseif extension=="png" or extension=="jpg" or extension=="jpeg" then
				entries[#entries+1]={bytes=bytes,name=name,lowered=lowered,image=true}
			elseif MEDIA_EXTENSIONS[extension] then
				entries[#entries+1]={bytes=bytes,name=name,media=MEDIA_EXTENSIONS[extension]}
			end
		end
		local mains={}
		for _,entry in ipairs(entries) do
			if entry.image and hasGltf then
				externals[#externals+1]={bytes=entry.bytes,name=entry.lowered}
			else
				mains[#mains+1]=entry
			end
		end
		local ids={}
		for _,entry in ipairs(mains) do
			local isMesh=entry.mesh==true
			local target,options=defaults.imageTarget,nil
			if isMesh then
				target,options=defaults.meshTarget,defaults.meshOptions
			elseif entry.media then
				target,options=defaults.mediaTarget,defaults.mediaOptions
			end
			ids[#ids+1]=Worker.enqueue({
				bytes=entry.bytes,
				name=entry.name,
				kind=entry.media,
				externals=isMesh and #externals>0 and externals or nil,
				target=target,
				options=options,
			})
		end
		return ids,#mains
	end

	function Worker.runOne(entry)
		local job=Inbox.find(entry.id)
		if not job then return end
		Worker.busy=true
		Worker.current=entry.id
		local remaining=#Inbox.list("queued")
		if Worker.batchTotal<Worker.batchDone+remaining then Worker.batchTotal=Worker.batchDone+remaining end
		Progress.batch(Worker.batchDone+1,Worker.batchTotal)
		Inbox.setState(entry.id,"running",{Started=os.time()})
		local ok,instance,report=pcall(function()
			local request=pending[entry.id]
			if not request then
				request=decodeRequest(job)
				request.cleanup=false
				if request.upload==nil and (job:GetAttribute("Chunks") or 0)>0 then request.upload=entry.id end
			end
			return Api.execute(request,{jobId=entry.id,source=pending[entry.id] and "plugin" or "mcp",check=function() assert(alive(),"Plugin encerrado.") assert(not RunService:IsRunning(),"Play iniciado.") end})
		end)
		pending[entry.id]=nil
		if Inbox.find(entry.id) then
			if ok then
				Inbox.setState(entry.id,"done",{Result=report,Finished=os.time(),Error=nil})
				stripData(job)
				Worker.processed+=1
				Worker.lastMessage="Importado: "..report.path
			else
				local message=tostring(instance):match("^[^\n]+") or tostring(instance)
				Inbox.setState(entry.id,"failed",{Error=message:sub(1,900),Finished=os.time()})
				Worker.failed+=1
				Worker.lastMessage="Falhou: "..message
			end
		end
		Worker.batchDone+=1
		log(Worker.lastMessage)
		Worker.busy=false
		Worker.current=nil
	end

	function Worker.start()
		task.spawn(function()
			while alive() do
				local okRoot,root=pcall(Inbox.root)
				if okRoot then root:SetAttribute("WorkerHeartbeat",os.time()) end
				if okRoot and not RunService:IsRunning() then
					local queued=Inbox.list("queued")
					if queued[1] then
						local okRun,err=pcall(Worker.runOne,queued[1])
						if not okRun then
							Worker.busy=false
							Worker.current=nil
							warn("ImportMCP worker: "..tostring(err))
						end
						task.wait(0.15)
						continue
					elseif Worker.batchDone>0 then
						Worker.batchDone=0
						Worker.batchTotal=0
						Progress.batch(0,0)
					end
				end
				task.wait(0.5)
			end
		end)
	end

	return Worker
end
