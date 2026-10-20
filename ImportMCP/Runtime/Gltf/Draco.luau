local Draco={}

local MAGIC="DRACO"
local METADATA_FLAG=32768
local TRIANGULAR_MESH=1
local SEQUENTIAL=0
local EDGEBREAKER=1
local DECODER_QUANTIZATION=2
local DECODER_NORMALS=3
local PREDICTION_NONE=-2
local PREDICTION_DIFFERENCE=0
local TRANSFORM_WRAP=1
local TYPE_SIZES={[0]=0,1,1,2,2,4,4,8,8,4,8,1}
local ATTRIBUTE_NAMES={[0]="POSITION","NORMAL","COLOR","TEX_COORD","GENERIC"}

local function fail(message)
	error("Draco: "..message,0)
end

local Reader={}
Reader.__index=Reader

local function reader(data,offset,limit)
	return setmetatable({data=data,position=offset,limit=limit},Reader)
end

function Reader:need(count)
	if self.position+count>self.limit then fail("fluxo truncado.") end
end

function Reader:u8()
	self:need(1)
	local value=buffer.readu8(self.data,self.position)
	self.position+=1
	return value
end

function Reader:i8()
	self:need(1)
	local value=buffer.readi8(self.data,self.position)
	self.position+=1
	return value
end

function Reader:u16()
	self:need(2)
	local value=buffer.readu16(self.data,self.position)
	self.position+=2
	return value
end

function Reader:u32()
	self:need(4)
	local value=buffer.readu32(self.data,self.position)
	self.position+=4
	return value
end

function Reader:i32()
	self:need(4)
	local value=buffer.readi32(self.data,self.position)
	self.position+=4
	return value
end

function Reader:f32()
	self:need(4)
	local value=buffer.readf32(self.data,self.position)
	self.position+=4
	return value
end

function Reader:text(count)
	self:need(count)
	local value=buffer.readstring(self.data,self.position,count)
	self.position+=count
	return value
end

function Reader:skip(count)
	self:need(count)
	self.position+=count
end

function Reader:varint()
	local result=0
	local shift=1
	for _=1,5 do
		local byte=self:u8()
		result+=(byte%128)*shift
		if byte<128 then return result end
		shift*=128
	end
	fail("varint invalido.")
	return 0
end

local function zigzag(value)
	if value%2==0 then return value//2 end
	return -((value+1)//2)
end

local function skipMetadata(stream)
	local entries=stream:varint()
	for _=1,entries do
		stream:skip(stream:u8())
		stream:skip(stream:varint())
	end
	local blocks=stream:varint()
	for _=1,blocks do
		stream:skip(stream:u8())
		skipMetadata(stream)
	end
end

local function skipGeometryMetadata(stream)
	local count=stream:varint()
	for _=1,count do
		stream:varint()
		skipMetadata(stream)
	end
	skipMetadata(stream)
end

local function readHeader(stream)
	if stream:text(5)~=MAGIC then fail("bloco sem assinatura DRACO.") end
	local major=stream:u8()
	local minor=stream:u8()
	local encoderType=stream:u8()
	local method=stream:u8()
	local flags=stream:u16()
	return {major=major,minor=minor,version=major*10+minor,encoderType=encoderType,method=method,flags=flags}
end

function Draco.detect(data,offset,length)
	if typeof(data)~="buffer" then return false end
	offset=offset or 0
	length=length or buffer.len(data)-offset
	if offset<0 or length<11 or offset+length>buffer.len(data) then return false end
	return buffer.readstring(data,offset,5)==MAGIC
end

function Draco.inspect(data,offset,length)
	offset=offset or 0
	length=length or buffer.len(data)-offset
	local ok,info=pcall(readHeader,reader(data,offset,offset+length))
	if not ok then return nil end
	return {version=info.major.."."..info.minor,method=info.method==EDGEBREAKER and "edgebreaker" or "sequencial",mesh=info.encoderType==TRIANGULAR_MESH}
end

local function readConnectivity(stream,info,yield)
	local faces=stream:varint()
	local points=stream:varint()
	local mode=stream:u8()
	info.faces=faces
	info.points=points
	if faces<=0 or points<=0 then fail("a malha compactada esta vazia.") end
	if mode==0 then fail("os indices usam codificacao entropica rANS, que este motor ainda nao le.") end
	local total=faces*3
	local indices=table.create(total)
	if points<256 then
		for i=1,total do indices[i]=stream:u8() end
	elseif points<65536 then
		for i=1,total do indices[i]=stream:u16() end
	elseif points<2097152 then
		for i=1,total do indices[i]=stream:varint() end
	else
		for i=1,total do indices[i]=stream:u32() end
	end
	if yield then yield() end
	return indices
end

local function readDescriptors(stream,info)
	local count
	if info.version>=20 then count=stream:varint() else count=stream:u32() end
	if count<1 or count>32 then fail("quantidade de atributos invalida ("..tostring(count)..").") end
	local list=table.create(count)
	for index=1,count do
		local attType=stream:u8()
		local dataType=stream:u8()
		local components=stream:u8()
		local normalized=stream:u8()
		local uniqueId
		if info.version>=13 then uniqueId=stream:varint() else uniqueId=stream:u16() end
		if not TYPE_SIZES[dataType] or TYPE_SIZES[dataType]==0 then fail("tipo de dado "..tostring(dataType).." desconhecido.") end
		if components<1 or components>4 then fail("atributo com "..tostring(components).." componentes.") end
		list[index]={attType=attType,name=ATTRIBUTE_NAMES[attType] or "GENERIC",dataType=dataType,components=components,normalized=normalized~=0,uniqueId=uniqueId}
	end
	return list
end

local function readPortable(stream,descriptor,kind,count,yield)
	if kind==DECODER_NORMALS then fail("normais octaedrais ainda nao suportadas.") end
	local components=descriptor.components
	local total=count*components
	local method=stream:i8()
	local minValue,maxValue,maxDif
	if method~=PREDICTION_NONE then
		if method~=PREDICTION_DIFFERENCE then fail("o esquema de predicao "..tostring(method).." depende da tabela de cantos do edgebreaker, ainda nao suportada.") end
		local transform=stream:i8()
		if transform~=TRANSFORM_WRAP then fail("transformacao de predicao "..tostring(transform).." nao suportada.") end
		minValue=stream:i32()
		maxValue=stream:i32()
		if minValue>maxValue then fail("limites de predicao invalidos.") end
		maxDif=1+maxValue-minValue
	end
	local compressed=stream:u8()
	if compressed>0 then fail("os atributos usam codificacao entropica rANS, que este motor ainda nao le.") end
	local width=stream:u8()
	local values=table.create(total)
	if width==4 then
		for i=1,total do values[i]=stream:u32() end
	elseif width==2 then
		for i=1,total do values[i]=stream:u16() end
	elseif width==1 then
		for i=1,total do values[i]=stream:u8() end
	else
		fail("inteiros de "..tostring(width).." byte(s) nao suportados.")
	end
	for i=1,total do values[i]=zigzag(values[i]) end
	if method==PREDICTION_DIFFERENCE then
		local previous=table.create(components)
		for c=1,components do previous[c]=0 end
		for i=0,count-1 do
			local base=i*components
			for c=1,components do
				local predicted=previous[c]
				if predicted<minValue then predicted=minValue elseif predicted>maxValue then predicted=maxValue end
				local value=predicted+values[base+c]
				if value>maxValue then value-=maxDif elseif value<minValue then value+=maxDif end
				values[base+c]=value
				previous[c]=value
			end
			if yield and i>0 and i%8192==0 then yield() end
		end
	end
	return values
end

local function readTransform(stream,kind,descriptor)
	if kind~=DECODER_QUANTIZATION then return nil end
	local components=descriptor.components
	local mins=table.create(components)
	for c=1,components do mins[c]=stream:f32() end
	local range=stream:f32()
	local bits=stream:u8()
	if bits<1 or bits>31 then fail("bits de quantizacao invalidos ("..tostring(bits)..").") end
	return {mins=mins,range=range,bits=bits}
end

local function finalize(descriptor,values,transform,count,yield)
	local components=descriptor.components
	if not transform then return {values=values,components=components,count=count} end
	local delta=transform.range/(2^transform.bits-1)
	local mins=transform.mins
	local out=table.create(count*components)
	for i=0,count-1 do
		local base=i*components
		for c=1,components do out[base+c]=mins[c]+values[base+c]*delta end
		if yield and i>0 and i%8192==0 then yield() end
	end
	return {values=out,components=components,count=count}
end

function Draco.decode(data,offset,length,yield)
	offset=offset or 0
	length=length or buffer.len(data)-offset
	local stream=reader(data,offset,offset+length)
	local info=readHeader(stream)
	if info.encoderType~=TRIANGULAR_MESH then fail("o bloco contem uma nuvem de pontos, nao uma malha triangular.") end
	if info.version<20 then fail("bitstream "..info.major.."."..info.minor.." e antigo demais; reexporte com uma versao atual do Draco.") end
	if info.flags>=METADATA_FLAG then skipGeometryMetadata(stream) end
	local indices
	if info.method==SEQUENTIAL then
		indices=readConnectivity(stream,info,yield)
	elseif info.method==EDGEBREAKER then
		fail("a malha usa conectividade edgebreaker, que este motor ainda nao le.")
	else
		fail("metodo de codificacao "..tostring(info.method).." desconhecido.")
	end
	local decoders=stream:u8()
	if decoders<1 or decoders>8 then fail("quantidade de decodificadores de atributo invalida.") end
	local groups=table.create(decoders)
	for index=1,decoders do
		local descriptors=readDescriptors(stream,info)
		local kinds=table.create(#descriptors)
		for i=1,#descriptors do kinds[i]=stream:u8() end
		groups[index]={descriptors=descriptors,kinds=kinds}
	end
	local attributes={}
	for _,group in ipairs(groups) do
		local portable=table.create(#group.descriptors)
		for i,descriptor in ipairs(group.descriptors) do
			portable[i]=readPortable(stream,descriptor,group.kinds[i],info.points,yield)
		end
		local transforms=table.create(#group.descriptors)
		for i,descriptor in ipairs(group.descriptors) do
			transforms[i]=readTransform(stream,group.kinds[i],descriptor)
		end
		for i,descriptor in ipairs(group.descriptors) do
			attributes[descriptor.uniqueId]=finalize(descriptor,portable[i],transforms[i],info.points,yield)
		end
	end
	return {indices=indices,points=info.points,faces=info.faces,attributes=attributes}
end

return table.freeze(Draco)
