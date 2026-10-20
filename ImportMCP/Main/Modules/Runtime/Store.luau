local Limits=require(script.Parent.Limits)
local Base64=require(script.Parent.Base64)

local Store={CHUNK=Limits.STORE_CHUNK,FOLDER="Payload"}

local function integer(value,low,high,label)
	assert(type(value)=="number" and value==value and value%1==0 and value>=low and value<=high,label.." invalido.")
	return value
end

function Store.write(container,data,format,yield)
	assert(typeof(container)=="Instance","Container invalido.")
	assert(typeof(data)=="buffer" and buffer.len(data)>0,"Payload vazio.")
	assert(type(format)=="string" and #format>0 and #format<=16,"Formato do payload invalido.")
	local existing=container:FindFirstChild(Store.FOLDER)
	if existing then existing:Destroy() end
	local text=Base64.encode(data,yield)
	local folder=Instance.new("Folder")
	folder.Name=Store.FOLDER
	local ok,err=pcall(function()
		local count=math.ceil(#text/Store.CHUNK)
		folder:SetAttribute("Format",format)
		folder:SetAttribute("Version",1)
		folder:SetAttribute("ChunkCount",count)
		folder:SetAttribute("EncodedBytes",#text)
		folder:SetAttribute("BinaryBytes",buffer.len(data))
		for index=1,count do
			local chunk=Instance.new("StringValue")
			chunk.Name=string.format("Data_%04d",index)
			chunk.Value=text:sub((index-1)*Store.CHUNK+1,index*Store.CHUNK)
			chunk.Parent=folder
			if yield and index%64==0 then yield() end
		end
		folder.Parent=container
	end)
	if not ok then
		folder:Destroy()
		error(err,0)
	end
	return folder
end

function Store.info(container)
	local folder=container and container:FindFirstChild(Store.FOLDER)
	if not folder or not folder:IsA("Folder") then return nil end
	return {format=folder:GetAttribute("Format"),chunks=folder:GetAttribute("ChunkCount"),encodedBytes=folder:GetAttribute("EncodedBytes"),binaryBytes=folder:GetAttribute("BinaryBytes")}
end

function Store.read(container,expectedFormat,yield)
	assert(typeof(container)=="Instance","Container invalido.")
	local folder=container:FindFirstChild(Store.FOLDER)
	assert(folder and folder:IsA("Folder"),"Payload ausente em "..container:GetFullName()..".")
	assert(folder:GetAttribute("Version")==1,"Versao do payload incompativel.")
	local format=folder:GetAttribute("Format")
	assert(type(format)=="string","Formato do payload ausente.")
	if expectedFormat then assert(format==expectedFormat,"Formato do payload inesperado: "..format..".") end
	local maxEncoded=math.ceil(Limits.MAX_BYTES/3)*4
	local count=integer(folder:GetAttribute("ChunkCount"),1,math.ceil(maxEncoded/Store.CHUNK),"Chunks")
	local encoded=integer(folder:GetAttribute("EncodedBytes"),1,maxEncoded,"Bytes codificados")
	local bytes=integer(folder:GetAttribute("BinaryBytes"),1,Limits.MAX_BYTES,"Bytes binarios")
	assert(count==math.ceil(encoded/Store.CHUNK),"Manifesto de chunks inconsistente.")
	local chunks=table.create(count)
	for index=1,count do
		local chunk=folder:FindFirstChild(string.format("Data_%04d",index))
		assert(chunk and chunk:IsA("StringValue"),"Chunk ausente: "..index)
		local expected=math.min(Store.CHUNK,encoded-(index-1)*Store.CHUNK)
		assert(#chunk.Value==expected,"Chunk truncado: "..index)
		chunks[index]=chunk.Value
		if yield and index%64==0 then yield() end
	end
	local data=Base64.decode(table.concat(chunks),yield,Limits.MAX_BYTES)
	assert(buffer.len(data)==bytes,"Tamanho binario inconsistente.")
	return data,format
end

return table.freeze(Store)
