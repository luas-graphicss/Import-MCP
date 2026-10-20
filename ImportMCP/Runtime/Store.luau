local Limits=require(script.Parent.Limits)
local Base64=require(script.Parent.Base64)

local FORMAT="IMCP1"

local Store={CHUNK=Limits.STORE_CHUNK}

function Store.checksum(data,length)
	local a,b=1,0
	local n=length or buffer.len(data)
	for first=0,n-1,5552 do
		for i=first,math.min(first+5551,n-1) do
			a+=buffer.readu8(data,i)
			b+=a
		end
		a%=65521
		b%=65521
	end
	return b*65536+a
end

function Store.hash(data)
	return string.format("%08x-%d",Store.checksum(data),buffer.len(data))
end

function Store.write(parent,name,data,yield)
	assert(typeof(data)=="buffer" and buffer.len(data)>0,"Store.write requer buffer nao vazio.")
	assert(buffer.len(data)<=Limits.MAX_SOURCE_BYTES,"Payload excede o limite de "..math.floor(Limits.MAX_SOURCE_BYTES/1048576).." MiB.")
	assert(not parent:FindFirstChild(name),"Ja existe um payload chamado "..name..".")
	local text=Base64.encode(data,yield)
	local folder=Instance.new("Folder")
	folder.Name=name
	local ok,err=pcall(function()
		local count=math.ceil(#text/Store.CHUNK)
		folder:SetAttribute("Format",FORMAT)
		folder:SetAttribute("ChunkCount",count)
		folder:SetAttribute("EncodedBytes",#text)
		folder:SetAttribute("BinaryBytes",buffer.len(data))
		folder:SetAttribute("Checksum",Store.checksum(data))
		for i=1,count do
			local chunk=Instance.new("StringValue")
			chunk.Name=string.format("Data_%04d",i)
			chunk.Value=string.sub(text,(i-1)*Store.CHUNK+1,i*Store.CHUNK)
			chunk.Parent=folder
			if yield and i%32==0 then yield() end
		end
		folder.Parent=parent
	end)
	if not ok then
		folder:Destroy()
		error(err,0)
	end
	return folder
end

function Store.replace(parent,name,data,yield)
	local existing=parent:FindFirstChild(name)
	if existing then existing:Destroy() end
	return Store.write(parent,name,data,yield)
end

function Store.read(folder,yield)
	assert(typeof(folder)=="Instance" and folder:IsA("Folder"),"Payload ausente.")
	assert(folder:GetAttribute("Format")==FORMAT,"Formato de payload incompativel: "..tostring(folder:GetAttribute("Format")))
	local count=folder:GetAttribute("ChunkCount")
	local encoded=folder:GetAttribute("EncodedBytes")
	local bytes=folder:GetAttribute("BinaryBytes")
	local checksum=folder:GetAttribute("Checksum")
	assert(type(count)=="number" and count>=1,"Manifesto de chunks invalido.")
	assert(type(encoded)=="number" and encoded>=1,"Manifesto de bytes invalido.")
	assert(type(bytes)=="number" and bytes>=1 and bytes<=Limits.MAX_SOURCE_BYTES,"Tamanho binario invalido.")
	assert(count==math.ceil(encoded/Store.CHUNK),"Manifesto de chunks inconsistente.")
	local chunks=table.create(count)
	for i=1,count do
		local chunk=folder:FindFirstChild(string.format("Data_%04d",i))
		assert(chunk and chunk:IsA("StringValue"),"Chunk ausente: "..i)
		local expected=math.min(Store.CHUNK,encoded-(i-1)*Store.CHUNK)
		assert(#chunk.Value==expected,"Chunk truncado: "..i)
		chunks[i]=chunk.Value
		if yield and i%32==0 then yield() end
	end
	local data=Base64.decode(table.concat(chunks),Limits.MAX_SOURCE_BYTES,yield)
	assert(buffer.len(data)==bytes,"Tamanho binario inconsistente apos decodificar.")
	if type(checksum)=="number" then
		assert(Store.checksum(data)==checksum,"Checksum do payload incorreto; fonte corrompida.")
	end
	return data
end

return table.freeze(Store)
