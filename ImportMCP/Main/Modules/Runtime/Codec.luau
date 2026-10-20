local Limits=require(script.Parent.Limits)
local ImageDecode=require(script.Parent.ImageDecode)
local HttpService=game:GetService("HttpService")

 
 
 
 
 
local Codec={MAGIC="IMC1",VERSION=2,VERTEX_STRIDE=26,INDEX_STRIDE=12,FLAG_COLORS=1,FLAG_SKIN=2,NO_BONE=65535}

local COLLISIONS={Default=true,Hull=true,Box=true,PreciseConvexDecomposition=true}

local function integer(value,low,high,label)
	assert(type(value)=="number" and value==value and value%1==0 and value>=low and value<=high,label.." invalido.")
	return value
end

local function finite(value)
	return type(value)=="number" and value==value and value>-math.huge and value<math.huge
end

local function hasFlag(flags,flag)
	return (flags or 0)%(flag*2)>=flag
end

function Codec.stride(flags)
	local stride=Codec.VERTEX_STRIDE
	if hasFlag(flags,Codec.FLAG_COLORS) then stride+=4 end
	if hasFlag(flags,Codec.FLAG_SKIN) then stride+=16 end
	return stride
end

function Codec.skinOffset(flags)
	return Codec.VERTEX_STRIDE+(hasFlag(flags,Codec.FLAG_COLORS) and 4 or 0)
end

function Codec.checksum(data,length)
	local a,b=1,0
	local total=length or buffer.len(data)
	for first=0,total-1,5552 do
		for index=first,math.min(first+5551,total-1) do
			a+=buffer.readu8(data,index)
			b+=a
		end
		a%=65521
		b%=65521
	end
	return b*65536+a
end

function Codec.meta(meta)
	assert(type(meta)=="table","Metadados ausentes.")
	assert(type(meta.name)=="string" and #meta.name>0 and #meta.name<=100 and utf8.len(meta.name),"Nome invalido.")
	local collision=meta.collision or "Default"
	assert(COLLISIONS[collision],"Colisao invalida.")
	local out={}
	for key,value in pairs(meta) do out[key]=value end
	out.collision=collision
	out.doubleSided=meta.doubleSided==true
	out.anchored=meta.anchored~=false
	out.canCollide=meta.canCollide~=false
	return out
end

function Codec.readVertex(group,index)
	local at=(index-1)*(group.stride or Codec.VERTEX_STRIDE)
	local data=group.vertexData
	return Vector3.new(buffer.readf32(data,at),buffer.readf32(data,at+4),buffer.readf32(data,at+8)),
		Vector3.new(buffer.readi16(data,at+12)/32767,buffer.readi16(data,at+14)/32767,buffer.readi16(data,at+16)/32767),
		Vector2.new(buffer.readf32(data,at+18),buffer.readf32(data,at+22))
end

function Codec.readPosition(group,index)
	local at=(index-1)*(group.stride or Codec.VERTEX_STRIDE)
	local data=group.vertexData
	return Vector3.new(buffer.readf32(data,at),buffer.readf32(data,at+4),buffer.readf32(data,at+8))
end

 
function Codec.readColor(group,index)
	if not hasFlag(group.flags,Codec.FLAG_COLORS) then return nil end
	local at=(index-1)*(group.stride or Codec.stride(group.flags))+Codec.VERTEX_STRIDE
	local data=group.vertexData
	return Color3.fromRGB(buffer.readu8(data,at),buffer.readu8(data,at+1),buffer.readu8(data,at+2)),buffer.readu8(data,at+3)/255
end

 
function Codec.readSkin(group,index)
	if not hasFlag(group.flags,Codec.FLAG_SKIN) then return nil end
	local at=(index-1)*(group.stride or Codec.stride(group.flags))+Codec.skinOffset(group.flags)
	local data=group.vertexData
	local bones,weights={},{}
	for k=0,3 do
		local bone=buffer.readu16(data,at+k*2)
		local weight=buffer.readu16(data,at+8+k*2)
		if bone~=Codec.NO_BONE and weight>0 then
			bones[#bones+1]=bone+1
			weights[#weights+1]=weight/65535
		end
	end
	return bones,weights
end

function Codec.readTriangle(group,index)
	local at=(index-1)*Codec.INDEX_STRIDE
	local data=group.indexData
	return buffer.readu32(data,at)+1,buffer.readu32(data,at+4)+1,buffer.readu32(data,at+8)+1
end

function Codec.writeVertex(data,index,position,normal,uv,stride)
	local at=(index-1)*(stride or Codec.VERTEX_STRIDE)
	buffer.writef32(data,at,position.X)
	buffer.writef32(data,at+4,position.Y)
	buffer.writef32(data,at+8,position.Z)
	buffer.writei16(data,at+12,math.round(math.clamp(normal.X,-1,1)*32767))
	buffer.writei16(data,at+14,math.round(math.clamp(normal.Y,-1,1)*32767))
	buffer.writei16(data,at+16,math.round(math.clamp(normal.Z,-1,1)*32767))
	buffer.writef32(data,at+18,uv.X)
	buffer.writef32(data,at+22,uv.Y)
end

function Codec.writeColor(data,index,stride,color,alpha)
	local at=(index-1)*stride+Codec.VERTEX_STRIDE
	buffer.writeu8(data,at,math.round(math.clamp(color.R,0,1)*255))
	buffer.writeu8(data,at+1,math.round(math.clamp(color.G,0,1)*255))
	buffer.writeu8(data,at+2,math.round(math.clamp(color.B,0,1)*255))
	buffer.writeu8(data,at+3,math.round(math.clamp(alpha or 1,0,1)*255))
end

 
function Codec.writeSkin(data,index,stride,flags,bones,weights)
	local at=(index-1)*stride+Codec.skinOffset(flags)
	local total=0
	for k=1,math.min(#bones,4) do total+=math.max(weights[k] or 0,0) end
	for k=0,3 do
		local bone=bones[k+1]
		local weight=weights[k+1] or 0
		if bone and weight>0 and total>0 then
			buffer.writeu16(data,at+k*2,bone-1)
			buffer.writeu16(data,at+8+k*2,math.clamp(math.round(weight/total*65535),1,65535))
		else
			buffer.writeu16(data,at+k*2,Codec.NO_BONE)
			buffer.writeu16(data,at+8+k*2,0)
		end
	end
end

function Codec.writeTriangle(data,index,a,b,c)
	local at=(index-1)*Codec.INDEX_STRIDE
	buffer.writeu32(data,at,a-1)
	buffer.writeu32(data,at+4,b-1)
	buffer.writeu32(data,at+8,c-1)
end

local function validateBones(bones)
	assert(type(bones)=="table" and #bones<=Limits.MAX_BONES,"Tabela de ossos invalida.")
	for index,bone in ipairs(bones) do
		assert(type(bone)=="table","Osso "..index.." invalido.")
		bone.name=tostring(bone.name or ("Bone_"..index)):sub(1,100)
		assert(#bone.name>0,"Osso "..index.." sem nome.")
		if bone.parent~=nil then
			integer(bone.parent,1,index-1,"Pai do osso "..index)
		end
		assert(typeof(bone.cframe)=="CFrame","CFrame do osso "..index.." invalido.")
		for _,value in ipairs({bone.cframe:GetComponents()}) do
			assert(finite(value) and math.abs(value)<=1e6,"CFrame do osso "..index.." fora da faixa.")
		end
	end
	return bones
end

function Codec.validate(snapshot,yield)
	assert(type(snapshot)=="table","Snapshot ausente.")
	snapshot.meta=Codec.meta(snapshot.meta)
	assert(type(snapshot.groups)=="table" and #snapshot.groups>=1 and #snapshot.groups<=256,"Grupos invalidos.")
	local textures=snapshot.textures or {}
	assert(type(textures)=="table" and #textures<=64,"Texturas invalidas.")
	for index,texture in ipairs(textures) do
		assert(type(texture)=="table" and typeof(texture.bytes)=="buffer","Textura "..index.." invalida.")
		assert(buffer.len(texture.bytes)>=16 and buffer.len(texture.bytes)<=Limits.MAX_IMAGE_BYTES,"Textura "..index.." com tamanho invalido.")
		assert(ImageDecode.FORMAT_CODES[texture.format],"Formato de textura "..index.." desconhecido.")
	end
	snapshot.bones=validateBones(snapshot.bones or {})
	local boneCount=#snapshot.bones
	local totalVertices,totalTriangles=0,0
	for gi,group in ipairs(snapshot.groups) do
		assert(type(group)=="table","Grupo "..gi.." invalido.")
		group.name=tostring(group.name or ("Grupo"..gi)):sub(1,100)
		group.flags=integer(group.flags or 0,0,3,"Flags do grupo "..gi)
		group.stride=Codec.stride(group.flags)
		local vc=integer(group.vertexCount,3,Limits.VERTICES,"Vertices do grupo "..gi)
		local tc=integer(group.triangleCount,1,Limits.TRIANGLES,"Triangulos do grupo "..gi)
		assert(typeof(group.vertexData)=="buffer" and buffer.len(group.vertexData)==vc*group.stride,"Vertices do grupo "..gi.." incompletos.")
		assert(typeof(group.indexData)=="buffer" and buffer.len(group.indexData)==tc*Codec.INDEX_STRIDE,"Indices do grupo "..gi.." incompletos.")
		if group.texture~=nil then
			integer(group.texture,1,#textures,"Textura do grupo "..gi)
		end
		assert(typeof(group.color)=="Color3","Cor do grupo "..gi.." invalida.")
		group.transparency=math.clamp(tonumber(group.transparency) or 0,0,1)
		group.doubleSided=group.doubleSided==true
		local skinned=hasFlag(group.flags,Codec.FLAG_SKIN)
		assert(not skinned or boneCount>0,"Grupo "..gi.." tem skinning mas o snapshot nao tem ossos.")
		local skinAt=Codec.skinOffset(group.flags)
		for vi=1,vc do
			local at=(vi-1)*group.stride
			for offset=0,8,4 do
				local value=buffer.readf32(group.vertexData,at+offset)
				assert(finite(value) and math.abs(value)<=1e6,"Posicao invalida no grupo "..gi..".")
			end
			if skinned then
				local weightTotal=0
				for k=0,3 do
					local bone=buffer.readu16(group.vertexData,at+skinAt+k*2)
					local weight=buffer.readu16(group.vertexData,at+skinAt+8+k*2)
					assert(bone==Codec.NO_BONE or bone<boneCount,"Osso fora da tabela no grupo "..gi..".")
					if bone~=Codec.NO_BONE then weightTotal+=weight end
				end
				assert(weightTotal>0,"Vertice sem peso de osso no grupo "..gi..".")
			end
			if yield and vi%Limits.YIELD_EVERY==0 then yield() end
		end
		for ti=1,tc do
			local a,b,c=Codec.readTriangle(group,ti)
			assert(a<=vc and b<=vc and c<=vc,"Indice fora do grupo "..gi..".")
			assert(a~=b and b~=c and a~=c,"Triangulo repetido no grupo "..gi..".")
			if yield and ti%Limits.YIELD_EVERY==0 then yield() end
		end
		totalVertices+=vc
		totalTriangles+=tc
	end
	assert(totalVertices<=Limits.VERTICES and totalTriangles<=Limits.TRIANGLES,"Modelo excede a capacidade logica do runtime.")
	snapshot.textures=textures
	return snapshot
end

local function boneBytes(bone)
	return 2+#bone.name+4+48
end

function Codec.encode(snapshot,yield)
	Codec.validate(snapshot,yield)
	local meta=HttpService:JSONEncode(snapshot.meta)
	assert(#meta<=Limits.MAX_META,"Metadados grandes demais.")
	local length=24+#meta
	for _,bone in ipairs(snapshot.bones) do length+=boneBytes(bone) end
	for _,group in ipairs(snapshot.groups) do
		length+=4+#group.name+20+buffer.len(group.vertexData)+buffer.len(group.indexData)
	end
	for _,texture in ipairs(snapshot.textures) do
		length+=13+buffer.len(texture.bytes)
	end
	length+=4
	assert(length<=Limits.MAX_BYTES,"Snapshot excede "..(Limits.MAX_BYTES//1048576).." MiB.")
	local data=buffer.create(length)
	buffer.writestring(data,0,Codec.MAGIC)
	buffer.writeu32(data,4,Codec.VERSION)
	buffer.writeu32(data,8,#meta)
	buffer.writeu32(data,12,#snapshot.groups)
	buffer.writeu32(data,16,#snapshot.textures)
	buffer.writeu32(data,20,#snapshot.bones)
	buffer.writestring(data,24,meta)
	local offset=24+#meta
	for _,bone in ipairs(snapshot.bones) do
		buffer.writeu16(data,offset,#bone.name)
		buffer.writestring(data,offset+2,bone.name)
		offset+=2+#bone.name
		buffer.writei32(data,offset,bone.parent and bone.parent-1 or -1)
		offset+=4
		local components={bone.cframe:GetComponents()}
		for k=1,12 do buffer.writef32(data,offset+(k-1)*4,components[k]) end
		offset+=48
	end
	for _,group in ipairs(snapshot.groups) do
		buffer.writeu32(data,offset,#group.name)
		buffer.writestring(data,offset+4,group.name)
		offset+=4+#group.name
		buffer.writeu32(data,offset,group.vertexCount)
		buffer.writeu32(data,offset+4,group.triangleCount)
		buffer.writeu32(data,offset+8,group.texture or 0)
		buffer.writeu8(data,offset+12,math.round(group.color.R*255))
		buffer.writeu8(data,offset+13,math.round(group.color.G*255))
		buffer.writeu8(data,offset+14,math.round(group.color.B*255))
		buffer.writeu8(data,offset+15,math.round(group.transparency*255))
		buffer.writeu8(data,offset+16,group.doubleSided and 1 or 0)
		buffer.writeu8(data,offset+17,group.flags or 0)
		buffer.writeu8(data,offset+18,0)
		buffer.writeu8(data,offset+19,0)
		offset+=20
		buffer.copy(data,offset,group.vertexData)
		offset+=buffer.len(group.vertexData)
		buffer.copy(data,offset,group.indexData)
		offset+=buffer.len(group.indexData)
		if yield then yield() end
	end
	for _,texture in ipairs(snapshot.textures) do
		buffer.writeu8(data,offset,ImageDecode.FORMAT_CODES[texture.format])
		buffer.writeu32(data,offset+1,0)
		buffer.writeu32(data,offset+5,0)
		buffer.writeu32(data,offset+9,buffer.len(texture.bytes))
		offset+=13
		buffer.copy(data,offset,texture.bytes)
		offset+=buffer.len(texture.bytes)
		if yield then yield() end
	end
	assert(offset==length-4,"Erro interno de tamanho IMC1.")
	buffer.writeu32(data,offset,Codec.checksum(data,offset))
	return data
end

function Codec.decode(data,yield)
	assert(typeof(data)=="buffer","IMC1 requer buffer.")
	local length=buffer.len(data)
	assert(length>=28 and length<=Limits.MAX_BYTES,"Tamanho IMC1 invalido.")
	assert(buffer.readstring(data,0,4)==Codec.MAGIC,"Assinatura IMC1 ausente.")
	local version=buffer.readu32(data,4)
	assert(version==1 or version==2,"Versao IMC1 desconhecida ("..tostring(version).."); atualize o ImportMCP.")
	assert(buffer.readu32(data,length-4)==Codec.checksum(data,length-4),"Checksum IMC1 incorreto; payload corrompido.")
	local metaLength=integer(buffer.readu32(data,8),2,Limits.MAX_META,"Metadados")
	local groupCount=integer(buffer.readu32(data,12),1,256,"Grupos")
	local textureCount=integer(buffer.readu32(data,16),0,64,"Texturas")
	local boneCount=version>=2 and integer(buffer.readu32(data,20),0,Limits.MAX_BONES,"Ossos") or 0
	local ok,meta=pcall(function() return HttpService:JSONDecode(buffer.readstring(data,24,metaLength)) end)
	assert(ok and type(meta)=="table","Metadados JSON corrompidos.")
	local snapshot={meta=meta,groups={},textures={},bones={}}
	local offset=24+metaLength
	local last=length-4
	for bi=1,boneCount do
		assert(offset+6<=last,"Osso "..bi.." truncado.")
		local nameLength=integer(buffer.readu16(data,offset),1,100,"Nome do osso")
		local name=buffer.readstring(data,offset+2,nameLength)
		offset+=2+nameLength
		assert(offset+52<=last,"Osso "..bi.." truncado.")
		local parent=buffer.readi32(data,offset)
		offset+=4
		local components=table.create(12)
		for k=1,12 do components[k]=buffer.readf32(data,offset+(k-1)*4) end
		offset+=48
		snapshot.bones[bi]={name=name,parent=parent>=0 and parent+1 or nil,cframe=CFrame.new(table.unpack(components))}
	end
	for gi=1,groupCount do
		assert(offset+4<=last,"Grupo "..gi.." truncado.")
		local nameLength=integer(buffer.readu32(data,offset),0,100,"Nome do grupo")
		local name=buffer.readstring(data,offset+4,nameLength)
		offset+=4+nameLength
		assert(offset+20<=last,"Cabecalho do grupo "..gi.." truncado.")
		local vc=integer(buffer.readu32(data,offset),3,Limits.VERTICES,"Vertices")
		local tc=integer(buffer.readu32(data,offset+4),1,Limits.TRIANGLES,"Triangulos")
		local texture=buffer.readu32(data,offset+8)
		local color=Color3.fromRGB(buffer.readu8(data,offset+12),buffer.readu8(data,offset+13),buffer.readu8(data,offset+14))
		local transparency=buffer.readu8(data,offset+15)/255
		local doubleSided=buffer.readu8(data,offset+16)==1
		local flags=version>=2 and buffer.readu8(data,offset+17) or 0
		offset+=20
		local stride=Codec.stride(flags)
		local vertexBytes=vc*stride
		local indexBytes=tc*Codec.INDEX_STRIDE
		assert(offset+vertexBytes+indexBytes<=last,"Dados do grupo "..gi.." truncados.")
		local vertexData=buffer.create(vertexBytes)
		buffer.copy(vertexData,0,data,offset,vertexBytes)
		offset+=vertexBytes
		local indexData=buffer.create(indexBytes)
		buffer.copy(indexData,0,data,offset,indexBytes)
		offset+=indexBytes
		snapshot.groups[gi]={name=name,vertexCount=vc,triangleCount=tc,texture=texture>0 and texture or nil,color=color,transparency=transparency,doubleSided=doubleSided,flags=flags,stride=stride,vertexData=vertexData,indexData=indexData}
		if yield then yield() end
	end
	for ti=1,textureCount do
		assert(offset+13<=last,"Textura "..ti.." truncada.")
		local format=ImageDecode.FORMAT_NAMES[buffer.readu8(data,offset)]
		local size=buffer.readu32(data,offset+9)
		offset+=13
		assert(format and size>=16 and offset+size<=last,"Textura "..ti.." invalida.")
		local bytes=buffer.create(size)
		buffer.copy(bytes,0,data,offset,size)
		offset+=size
		snapshot.textures[ti]={format=format,bytes=bytes}
		if yield then yield() end
	end
	assert(offset==last,"Bytes adicionais no IMC1.")
	return Codec.validate(snapshot,yield)
end

return table.freeze(Codec)
