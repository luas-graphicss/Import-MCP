local Accessors={}

local components={
	[5120]={size=1,read=buffer.readi8,scale=127},
	[5121]={size=1,read=buffer.readu8,scale=255},
	[5122]={size=2,read=buffer.readi16,scale=32767},
	[5123]={size=2,read=buffer.readu16,scale=65535},
	[5124]={size=4,read=buffer.readi32},
	[5125]={size=4,read=buffer.readu32},
	[5126]={size=4,read=buffer.readf32},
}

local widths={SCALAR=1,VEC2=2,VEC3=3,VEC4=4,MAT2=4,MAT3=9,MAT4=16}

local function compressionOf(entry)
	local extensions=entry.extensions
	if type(extensions)~="table" then return nil end
	if extensions["EXT_meshopt_compression"]~=nil then return "compressao meshopt (EXT_meshopt_compression)" end
	return nil
end

local function resolveView(doc,index)
	assert(type(index)=="number","BufferView invalido no arquivo.")
	local views=doc.json.bufferViews
	local entry=views and views[index+1]
	assert(entry,"BufferView "..tostring(index).." ausente no arquivo.")
	local compression=compressionOf(entry)
	assert(not compression,"O arquivo usa "..tostring(compression)..", que este importador nao le. Baixe ou exporte o modelo sem compressao de malha.")
	local data=doc.buffers[(entry.buffer or 0)+1]
	assert(data,"Buffer "..tostring(entry.buffer or 0).." nao foi resolvido.")
	return entry,data
end

function Accessors.info(doc,index)
	assert(type(index)=="number","Accessor invalido no arquivo.")
	local entry=doc.json.accessors and doc.json.accessors[index+1]
	assert(entry,"Accessor "..tostring(index).." ausente no arquivo.")
	local spec=components[entry.componentType]
	assert(spec,"Componente glTF nao suportado: "..tostring(entry.componentType))
	local width=widths[entry.type]
	assert(width,"Tipo de accessor nao suportado: "..tostring(entry.type))
	return entry,spec,width
end

function Accessors.dataless(doc,index)
	if type(index)~="number" then return true end
	local entry=doc.json.accessors and doc.json.accessors[index+1]
	if type(entry)~="table" then return true end
	if entry.bufferView~=nil then return false end
	local sparse=entry.sparse
	if type(sparse)=="table" and (tonumber(sparse.count) or 0)>0 then return false end
	return true
end

function Accessors.read(doc,index,yield)
	local entry,spec,width=Accessors.info(doc,index)
	local count=tonumber(entry.count) or 0
	assert(count>=0 and count<=4000000,"Accessor com contagem invalida: "..tostring(entry.count))
	local values=table.create(count*width,0)
	local filled=false
	if entry.bufferView~=nil then
		local view,data=resolveView(doc,entry.bufferView)
		local element=spec.size*width
		local stride=tonumber(view.byteStride) or element
		assert(stride>=element,"byteStride menor que o elemento do accessor.")
		local base=(tonumber(view.byteOffset) or 0)+(tonumber(entry.byteOffset) or 0)
		local length=buffer.len(data)
		local read=spec.read
		local size=spec.size
		for i=0,count-1 do
			local offset=base+i*stride
			assert(offset>=0 and offset+element<=length,"Dados binarios insuficientes para o accessor.")
			local slot=i*width
			for c=0,width-1 do values[slot+c+1]=read(data,offset+c*size) end
			if yield and i>0 and i%20000==0 then yield() end
		end
		if entry.normalized and spec.scale then
			for i=1,count*width do values[i]=math.clamp(values[i]/spec.scale,-1,1) end
		end
		filled=count>0
	end
	local sparse=entry.sparse
	if type(sparse)=="table" and (tonumber(sparse.count) or 0)>0 then
		local indices=sparse.indices
		local replacement=sparse.values
		assert(type(indices)=="table" and type(replacement)=="table","Accessor sparse invalido.")
		local indexSpec=components[indices.componentType]
		assert(indexSpec,"Componente sparse nao suportado: "..tostring(indices.componentType))
		local indexView,indexData=resolveView(doc,indices.bufferView)
		local valueView,valueData=resolveView(doc,replacement.bufferView)
		local indexBase=(tonumber(indexView.byteOffset) or 0)+(tonumber(indices.byteOffset) or 0)
		local valueBase=(tonumber(valueView.byteOffset) or 0)+(tonumber(replacement.byteOffset) or 0)
		local indexStride=tonumber(indexView.byteStride) or indexSpec.size
		local valueStride=tonumber(valueView.byteStride) or spec.size*width
		for k=0,sparse.count-1 do
			local at=indexBase+k*indexStride
			assert(at+indexSpec.size<=buffer.len(indexData),"Indices sparse insuficientes.")
			local target=indexSpec.read(indexData,at)
			assert(target>=0 and target<count,"Indice sparse fora do accessor.")
			local slot=target*width
			for c=0,width-1 do
				local from=valueBase+k*valueStride+c*spec.size
				assert(from+spec.size<=buffer.len(valueData),"Valores sparse insuficientes.")
				local value=spec.read(valueData,from)
				if entry.normalized and spec.scale then value=math.clamp(value/spec.scale,-1,1) end
				values[slot+c+1]=value
			end
			if yield and k>0 and k%20000==0 then yield() end
		end
		filled=true
	end
	return values,width,count,filled
end

return table.freeze(Accessors)
