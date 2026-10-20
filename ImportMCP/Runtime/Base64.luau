local alphabet="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local chars,values={},{}
for i=1,64 do
	local c=string.byte(alphabet,i)
	chars[i-1]=c
	values[c]=i-1
end
values[45]=62
values[95]=63

local Base64={}

function Base64.encode(data,yield)
	if type(data)=="string" then data=buffer.fromstring(data) end
	assert(typeof(data)=="buffer","Base64.encode requer buffer.")
	local n=buffer.len(data)
	local out=buffer.create(math.ceil(n/3)*4)
	local at=0
	for i=0,n-1,3 do
		local a=buffer.readu8(data,i)
		local b=i+1<n and buffer.readu8(data,i+1) or 0
		local c=i+2<n and buffer.readu8(data,i+2) or 0
		buffer.writeu8(out,at,chars[math.floor(a/4)])
		buffer.writeu8(out,at+1,chars[(a%4)*16+math.floor(b/16)])
		buffer.writeu8(out,at+2,i+1<n and chars[(b%16)*4+math.floor(c/64)] or 61)
		buffer.writeu8(out,at+3,i+2<n and chars[c%64] or 61)
		at+=4
		if yield and at%196608==0 then yield() end
	end
	return buffer.tostring(out)
end

function Base64.decode(text,maxBytes,yield)
	assert(type(text)=="string","Base64.decode requer string.")
	local clean=(text:gsub("[%s=]",""))
	local total=#clean
	assert(total>0,"Base64 vazio.")
	local size=math.floor(total*3/4)
	assert(not maxBytes or size<=maxBytes,"Payload excede o limite de bytes.")
	local out=buffer.create(size+3)
	local at=0
	local index=1
	while index+3<=total do
		local ca,cb,cc,cd=string.byte(clean,index,index+3)
		local a,b,c,d=values[ca],values[cb],values[cc],values[cd]
		assert(a and b and c and d,"Base64 com caractere invalido na posicao "..index..".")
		local value=a*262144+b*4096+c*64+d
		local first=value//65536
		local rest=value-first*65536
		local second=rest//256
		buffer.writeu8(out,at,first)
		buffer.writeu8(out,at+1,second)
		buffer.writeu8(out,at+2,rest-second*256)
		at+=3
		index+=4
		if yield and at%196608==0 then yield() end
	end
	local remainder=total-index+1
	if remainder==2 then
		local a,b=values[string.byte(clean,index)],values[string.byte(clean,index+1)]
		assert(a and b,"Base64 com caractere invalido no final.")
		buffer.writeu8(out,at,a*4+b//16)
		at+=1
	elseif remainder==3 then
		local a,b,c=values[string.byte(clean,index)],values[string.byte(clean,index+1)],values[string.byte(clean,index+2)]
		assert(a and b and c,"Base64 com caractere invalido no final.")
		local value=a*1024+b*16+c//4
		local first=value//256
		buffer.writeu8(out,at,first)
		buffer.writeu8(out,at+1,value-first*256)
		at+=2
	elseif remainder==1 then
		error("Base64 truncado.",0)
	end
	local result=buffer.create(at)
	if at>0 then buffer.copy(result,0,out,0,at) end
	return result
end

return table.freeze(Base64)
