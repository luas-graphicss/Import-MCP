local Binary={}

local decode={}
do
	local alphabet="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	for index=1,#alphabet do decode[string.byte(alphabet,index)]=index-1 end
	decode[45]=62
	decode[95]=63
end

function Binary.fromString(text)
	assert(type(text)=="string","Conteudo binario invalido.")
	return buffer.fromstring(text)
end

function Binary.base64(text,yield)
	assert(type(text)=="string","Conteudo base64 invalido.")
	local clean=(text:gsub("%s",""))
	clean=(clean:gsub("=+$",""))
	local total=#clean
	local out=buffer.create(math.floor(total*3/4)+3)
	local size=0
	local index=1
	while index+3<=total do
		local a,b,c,d=string.byte(clean,index,index+3)
		a=decode[a]
		b=decode[b]
		c=decode[c]
		d=decode[d]
		assert(a and b and c and d,"Base64 com caractere invalido.")
		local value=a*262144+b*4096+c*64+d
		local first=value//65536
		local rest=value-first*65536
		local second=rest//256
		buffer.writeu8(out,size,first)
		buffer.writeu8(out,size+1,second)
		buffer.writeu8(out,size+2,rest-second*256)
		size+=3
		index+=4
		if yield and size%98304==0 then yield() end
	end
	local remainder=total-index+1
	if remainder==2 then
		local a,b=string.byte(clean,index,index+1)
		a=decode[a]
		b=decode[b]
		assert(a and b,"Base64 com caractere invalido.")
		buffer.writeu8(out,size,a*4+b//16)
		size+=1
	elseif remainder==3 then
		local a,b,c=string.byte(clean,index,index+2)
		a=decode[a]
		b=decode[b]
		c=decode[c]
		assert(a and b and c,"Base64 com caractere invalido.")
		local value=a*1024+b*16+c//4
		local first=value//256
		buffer.writeu8(out,size,first)
		buffer.writeu8(out,size+1,value-first*256)
		size+=2
	elseif remainder==1 then
		error("Base64 truncado no arquivo.")
	end
	local result=buffer.create(size)
	if size>0 then buffer.copy(result,0,out,0,size) end
	return result
end

function Binary.slice(source,offset,length)
	assert(offset>=0 and length>=0 and offset+length<=buffer.len(source),"Fatia binaria fora do arquivo.")
	local out=buffer.create(length)
	if length>0 then buffer.copy(out,0,source,offset,length) end
	return out
end

function Binary.unescape(text)
	return (tostring(text):gsub("%%(%x%x)",function(hex) return string.char(tonumber(hex,16)) end))
end

function Binary.name(uri)
	local text=Binary.unescape((tostring(uri):gsub("%?.*$","")))
	return string.lower(text:match("([^/\\]+)$") or text)
end

function Binary.dataUri(uri,yield)
	if type(uri)~="string" then return nil end
	local head,payload=uri:match("^data:([^,]*),(.*)$")
	if not head then return nil end
	if string.find(string.lower(head),"base64",1,true) then return Binary.base64(payload,yield) end
	return buffer.fromstring(Binary.unescape(payload))
end

return table.freeze(Binary)
