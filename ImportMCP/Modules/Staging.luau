local Config=require(script.Parent.Config)
local Limits=require(script.Parent.Parent.Runtime.Limits)
local ServerStorage=game:GetService("ServerStorage")
local HttpService=game:GetService("HttpService")

local Staging={}

local function root(create)
	local folder=ServerStorage:FindFirstChild(Config.STAGING)
	if not folder and create then
		folder=Instance.new("Folder")
		folder.Name=Config.STAGING
		folder.Parent=ServerStorage
	end
	return folder
end

local function session(id)
	local folder=root(false)
	local found=folder and folder:FindFirstChild(tostring(id))
	assert(found and found:IsA("Folder"),"Sessao de upload nao encontrada: "..tostring(id))
	return found
end

local function chunkName(index)
	return string.format("Chunk_%05d",index)
end

local SLICE=Limits.STORE_CHUNK

local function putChunk(container,index,text)
	assert(type(index)=="number" and index>=1 and index%1==0,"Indice de chunk invalido.")
	assert(type(text)=="string" and #text>0,"Chunk vazio.")
	local existing=container:FindFirstChild(chunkName(index))
	if existing then existing:Destroy() end
	local folder=Instance.new("Folder")
	folder.Name=chunkName(index)
	local slices=math.ceil(#text/SLICE)
	folder:SetAttribute("Slices",slices)
	folder:SetAttribute("Length",#text)
	for i=1,slices do
		local value=Instance.new("StringValue")
		value.Name=string.format("Slice_%03d",i)
		value.Value=string.sub(text,(i-1)*SLICE+1,i*SLICE)
		value.Parent=folder
	end
	folder.Parent=container
	return slices
end

local function readChunk(folder)
	local slices=folder:GetAttribute("Slices") or 0
	local parts=table.create(slices)
	for i=1,slices do
		local value=folder:FindFirstChild(string.format("Slice_%03d",i))
		assert(value and value:IsA("StringValue"),"Fatia "..i.." ausente em "..folder.Name..".")
		parts[i]=value.Value
	end
	local text=table.concat(parts)
	assert(#text==(folder:GetAttribute("Length") or #text),"Chunk "..folder.Name.." truncado.")
	return text
end

local function countChunks(container)
	local total=0
	for _,child in ipairs(container:GetChildren()) do
		if child:IsA("Folder") and string.match(child.Name,"^Chunk_(%d+)$") then total+=1 end
	end
	return total
end

local function collect(container,expected)
	local ordered={}
	local highest=0
	for _,child in ipairs(container:GetChildren()) do
		if child:IsA("Folder") then
			local index=tonumber(string.match(child.Name,"^Chunk_(%d+)$"))
			if index then
				ordered[index]=child
				if index>highest then highest=index end
			end
		end
	end
	local count=expected and expected>0 and expected or highest
	local parts=table.create(count)
	for i=1,count do
		assert(ordered[i],"Chunk "..i.." ausente em "..container.Name..".")
		parts[i]=readChunk(ordered[i])
		if i%8==0 then task.wait() end
	end
	return table.concat(parts),count
end

function Staging.begin(spec)
	spec=spec or {}
	Staging.sweep()
	local id=HttpService:GenerateGUID(false)
	local folder=Instance.new("Folder")
	folder.Name=id
	folder:SetAttribute("Source",tostring(spec.name or "asset"))
	folder:SetAttribute("Kind",tostring(spec.kind or "auto"))
	folder:SetAttribute("Chunks",tonumber(spec.chunks) or 0)
	folder:SetAttribute("Received",0)
	folder:SetAttribute("Created",os.time())
	local externals=Instance.new("Folder")
	externals.Name="Externals"
	externals.Parent=folder
	folder.Parent=root(true)
	return id
end

function Staging.chunk(id,index,text)
	local folder=session(id)
	putChunk(folder,index,text)
	local received=countChunks(folder)
	folder:SetAttribute("Received",received)
	return {session=id,received=received,expected=folder:GetAttribute("Chunks")}
end

function Staging.external(id,fileName,index,text)
	local folder=session(id)
	local key=string.lower(tostring(fileName))
	assert(#key>0,"Nome do arquivo externo vazio.")
	local externals=folder:FindFirstChild("Externals")
	local container=externals:FindFirstChild(key)
	if not container then
		container=Instance.new("Folder")
		container.Name=key
		container.Parent=externals
	end
	putChunk(container,index or 1,text)
	return {session=id,external=key,chunks=countChunks(container)}
end

function Staging.assemble(id)
	local folder=session(id)
	local expected=folder:GetAttribute("Chunks") or 0
	local data,count=collect(folder,expected)
	assert(#data>0,"Sessao sem dados.")
	local externals={}
	local extra=folder:FindFirstChild("Externals")
	if extra then
		for _,container in ipairs(extra:GetChildren()) do
			if container:IsA("Folder") then externals[container.Name]=collect(container,0) end
		end
	end
	return {
		name=folder:GetAttribute("Source"),
		kind=folder:GetAttribute("Kind"),
		data=data,
		chunks=count,
		externals=externals,
	}
end

function Staging.abort(id)
	local folder=root(false)
	local found=folder and folder:FindFirstChild(tostring(id))
	if found then found:Destroy() end
	return found~=nil
end

function Staging.list()
	local out={}
	local folder=root(false)
	if not folder then return out end
	for _,child in ipairs(folder:GetChildren()) do
		if child:IsA("Folder") then
			out[#out+1]={
				session=child.Name,
				name=child:GetAttribute("Source"),
				kind=child:GetAttribute("Kind"),
				expected=child:GetAttribute("Chunks"),
				received=child:GetAttribute("Received"),
				age=os.time()-(child:GetAttribute("Created") or os.time()),
			}
		end
	end
	return out
end

function Staging.sweep()
	local folder=root(false)
	if not folder then return 0 end
	local removed=0
	for _,child in ipairs(folder:GetChildren()) do
		local created=child:GetAttribute("Created") or 0
		if os.time()-created>Config.STAGING_TTL then
			child:Destroy()
			removed+=1
		end
	end
	if #folder:GetChildren()==0 then folder:Destroy() end
	return removed
end

return table.freeze(Staging)
