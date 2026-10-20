local ALPHABET="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local chars,values={},{}
for index=1,64 do
	local code=string.byte(ALPHABET,index)
	chars[index-1]=code
	values[code]=index-1
end
values[45]=62
values[95]=63

local Base64={}

function Base64.encode(data,yield)
	assert(typeof(data)=="buffer","Base64.encode requer buffer.")
	local total=buffer.len(data)
	local out=buffer.create(math.ceil(total/3)*4)
	local at=0
	for index=0,total-1,3 do
		local a=buffer.readu8(data,index)
		local b=index+1<total and buffer.readu8(data,index+1) or 0
		local c=index+2<total and buffer.readu8(data,index+2) or 0
		buffer.writeu8(out,at,chars[a//4])
		buffer.writeu8(out,at+1,chars[(a%4)*16+b//16])
		buffer.writeu8(out,at+2,index+1<total and chars[(b%16)*4+c//64] or 61)
		buffer.writeu8(out,at+3,index+2<total and chars[c%64] or 61)
		at+=4
		if yield and at%262144==0 then yield() end
	end
	return buffer.tostring(out)
end

function Base64.decode(text,yield,maxBytes)
	assert(type(text)=="string","Base64 invalido.")
	local clean=(text:gsub("[%s=]",""))
	local total=#clean
	local remainder=total%4
	assert(remainder~=1,"Base64 truncado.")
	local size=(total//4)*3+(remainder==2 and 1 or remainder==3 and 2 or 0)
	if maxBytes then assert(size<=maxBytes,"Payload excede o limite de "..maxBytes.." bytes.") end
	local out=buffer.create(size)
	local at=0
	local index=1
	while index+3<=total do
		local a,b,c,d=string.byte(clean,index,index+3)
		a,b,c,d=values[a],values[b],values[c],values[d]
		assert(a and b and c and d,"Base64 com caractere invalido.")
		local value=a*262144+b*4096+c*64+d
		buffer.writeu8(out,at,value//65536)
		buffer.writeu8(out,at+1,(value//256)%256)
		buffer.writeu8(out,at+2,value%256)
		at+=3
		index+=4
		if yield and at%196608==0 then yield() end
	end
	if remainder==2 then
		local a,b=string.byte(clean,index,index+1)
		a,b=values[a],values[b]
		assert(a and b,"Base64 com caractere invalido.")
		buffer.writeu8(out,at,a*4+b//16)
	elseif remainder==3 then
		local a,b,c=string.byte(clean,index,index+2)
		a,b,c=values[a],values[b],values[c]
		assert(a and b and c,"Base64 com caractere invalido.")
		local value=a*1024+b*16+c//4
		buffer.writeu8(out,at,value//256)
		buffer.writeu8(out,at+1,value%256)
	end
	return out
end

return table.freeze(Base64)
