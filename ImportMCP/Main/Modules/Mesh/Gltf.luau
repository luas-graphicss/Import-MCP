local Binary=require(script.Parent.Binary)
local Accessors=require(script.Parent.Accessors)
local Nodes=require(script.Parent.Nodes)
local Draco=require(script.Parent.Draco)

local Gltf={}

local function clampColor(values)
	if type(values)~="table" then return nil end
	local r=tonumber(values[1]) or 1
	local g=tonumber(values[2]) or 1
	local b=tonumber(values[3]) or 1
	return Color3.new(math.clamp(r,0,1),math.clamp(g,0,1),math.clamp(b,0,1))
end

function Gltf.parse(contents,options)
	assert(type(contents)=="string" and #contents>=20,"Arquivo vazio ou pequeno demais para ser glTF/GLB.")
	local decodeJson=options and options.decodeJson
	assert(type(decodeJson)=="function","Decodificador JSON indisponivel.")
	local json,bin
	if string.sub(contents,1,4)=="glTF" then
		local data=buffer.fromstring(contents)
		local size=buffer.len(data)
		assert(size>=12,"GLB truncado.")
		local version=buffer.readu32(data,4)
		assert(version==2,"Somente GLB versao 2 e suportado (arquivo versao "..tostring(version)..").")
		local declared=buffer.readu32(data,8)
		local total=math.min(declared>0 and declared or size,size)
		local cursor=12
		while cursor+8<=total do
			local length=buffer.readu32(data,cursor)
			local kind=buffer.readu32(data,cursor+4)
			local start=cursor+8
			assert(start+length<=size,"Chunk GLB truncado.")
			if kind==0x4E4F534A and not json then
				json=decodeJson(buffer.readstring(data,start,length))
			elseif kind==0x004E4942 and not bin then
				bin=Binary.slice(data,start,length)
			end
			cursor=start+length
			if cursor%4~=0 then cursor+=4-cursor%4 end
		end
		assert(json,"GLB sem bloco JSON.")
	else
		json=decodeJson((contents:gsub("^\239\187\191","")))
	end
	assert(type(json)=="table","JSON do glTF invalido.")
	local asset=json.asset
	if type(asset)=="table" and asset.version~=nil then
		assert(string.sub(tostring(asset.version),1,1)=="2","Somente glTF 2.0 e suportado (arquivo "..tostring(asset.version)..").")
	end
	assert(type(json.meshes)=="table" and #json.meshes>0,"O arquivo nao contem malhas.")
	return {json=json,bin=bin,buffers={}}
end

function Gltf.resolveBuffers(doc,options)
	options=options or {}
	local externals=options.externals or {}
	doc.externals=externals
	local descriptors=doc.json.buffers or {}
	for index,descriptor in ipairs(descriptors) do
		local resolved
		if descriptor.uri==nil then
			assert(doc.bin,"O arquivo aponta para o buffer interno do GLB, mas ele nao existe.")
			resolved=doc.bin
		else
			resolved=Binary.dataUri(descriptor.uri,options.yield)
			if not resolved then
				local name=Binary.name(descriptor.uri)
				resolved=externals[name]
				assert(resolved,"O arquivo externo '"..name.."' nao foi enviado. Selecione tambem esse arquivo junto do .gltf ou exporte como .glb.")
			end
		end
		if type(descriptor.byteLength)=="number" then
			assert(buffer.len(resolved)+3>=descriptor.byteLength,"O buffer '"..tostring(descriptor.uri or "GLB").."' e menor que o declarado no arquivo.")
		end
		doc.buffers[index]=resolved
	end
	if #descriptors==0 and doc.bin then doc.buffers[1]=doc.bin end
	return doc
end

local TEXTURE_SLOTS={
	{key="baseColor",path={"pbrMetallicRoughness","baseColorTexture"}},
	{key="metallicRoughness",path={"pbrMetallicRoughness","metallicRoughnessTexture"}},
	{key="normal",path={"normalTexture"}},
	{key="occlusion",path={"occlusionTexture"}},
	{key="emissive",path={"emissiveTexture"}},
}

local function textureSource(json,reference)
	if type(reference)~="table" then return nil end
	local index=tonumber(reference.index)
	if not index then return nil end
	local texture=json.textures and json.textures[index+1]
	if type(texture)~="table" then return nil end
	local source=texture.source
	if source==nil and type(texture.extensions)=="table" then
		for _,entry in pairs(texture.extensions) do
			if type(entry)=="table" and entry.source~=nil then source=entry.source; break end
		end
	end
	return tonumber(source)
end

function Gltf.materialMaps(doc,index)
	if index==nil then return nil end
	local material=doc.json.materials and doc.json.materials[index+1]
	if type(material)~="table" then return nil end
	local maps=nil
	for _,slot in ipairs(TEXTURE_SLOTS) do
		local reference=material
		for _,step in ipairs(slot.path) do
			reference=type(reference)=="table" and reference[step] or nil
		end
		local source=textureSource(doc.json,reference)
		if source then
			maps=maps or {}
			maps[slot.key]=source
		end
	end
	local extensions=material.extensions
	local gloss=type(extensions)=="table" and extensions["KHR_materials_pbrSpecularGlossiness"] or nil
	if type(gloss)=="table" then
		local diffuse=textureSource(doc.json,gloss.diffuseTexture)
		local specular=textureSource(doc.json,gloss.specularGlossinessTexture)
		if diffuse or specular then maps=maps or {} end
		if diffuse and maps.baseColor==nil then maps.baseColor=diffuse end
		if specular and maps.metallicRoughness==nil then maps.metallicRoughness=specular end
	end
	return maps
end

function Gltf.imageBytes(doc,index,yield)
	if index==nil then return nil end
	local cache=doc.imageBytes
	if not cache then cache={}; doc.imageBytes=cache end
	local hit=cache[index]
	if hit~=nil then
		if hit==false then return nil end
		return hit
	end
	local descriptor=doc.json.images and doc.json.images[index+1]
	local bytes=nil
	if type(descriptor)=="table" then
		if type(descriptor.uri)=="string" then
			bytes=Binary.dataUri(descriptor.uri,yield)
			if not bytes then
				local supplied=(doc.externals or {})[Binary.name(descriptor.uri)]
				if type(supplied)=="string" then bytes=buffer.fromstring(supplied)
				elseif typeof(supplied)=="buffer" then bytes=supplied end
			end
		elseif descriptor.bufferView~=nil then
			local view=doc.json.bufferViews and doc.json.bufferViews[(tonumber(descriptor.bufferView) or 0)+1]
			if type(view)=="table" then
				local source=doc.buffers[(tonumber(view.buffer) or 0)+1]
				local offset=tonumber(view.byteOffset) or 0
				local length=tonumber(view.byteLength) or 0
				if source and length>0 and offset+length<=buffer.len(source) then
					bytes=Binary.slice(source,offset,length)
				end
			end
		end
	end
	cache[index]=bytes or false
	return bytes
end

function Gltf.materialColor(doc,index)
	if index==nil then return Color3.new(1,1,1) end
	local material=doc.json.materials and doc.json.materials[index+1]
	if type(material)~="table" then return Color3.new(1,1,1) end
	local pbr=material.pbrMetallicRoughness
	local color=type(pbr)=="table" and clampColor(pbr.baseColorFactor) or nil
	if not color then
		local extensions=material.extensions
		local gloss=type(extensions)=="table" and extensions["KHR_materials_pbrSpecularGlossiness"] or nil
		color=type(gloss)=="table" and clampColor(gloss.diffuseFactor) or nil
	end
	return color or Color3.new(1,1,1)
end

function Gltf.materialInfo(doc,index)
	local info={color=Gltf.materialColor(doc,index),alpha=1,doubleSided=false,alphaMode="OPAQUE"}
	if index==nil then return info end
	local material=doc.json.materials and doc.json.materials[index+1]
	if type(material)~="table" then return info end
	info.doubleSided=material.doubleSided==true
	info.alphaMode=type(material.alphaMode)=="string" and material.alphaMode or "OPAQUE"
	local pbr=material.pbrMetallicRoughness
	local factor=type(pbr)=="table" and pbr.baseColorFactor or nil
	if type(factor)=="table" and type(factor[4])=="number" then info.alpha=math.clamp(factor[4],0,1) end
	if info.alphaMode=="OPAQUE" then info.alpha=1 end
	return info
end

local UNSUPPORTED={["EXT_meshopt_compression"]="compressao meshopt (EXT_meshopt_compression)"}

local function finiteNumber(value)
	return type(value)=="number" and value==value and value>-math.huge and value<math.huge
end

function Gltf.unsupported(json)
	local names={}
	local required=type(json)=="table" and json.extensionsRequired or nil
	if type(required)=="table" then
		for _,name in ipairs(required) do
			local label=UNSUPPORTED[name]
			if label then names[#names+1]=label end
		end
	end
	return names
end

function Gltf.dracoMesh(doc,extension,yield)
	local index=tonumber(extension.bufferView)
	assert(index,"A primitiva Draco nao aponta para nenhum bufferView.")
	local cache=doc.dracoMeshes
	if not cache then cache={} doc.dracoMeshes=cache end
	local hit=cache[index]
	if hit~=nil then return hit end
	local view=doc.json.bufferViews and doc.json.bufferViews[index+1]
	assert(type(view)=="table","O bufferView "..index.." da malha Draco nao existe.")
	local source=doc.buffers[(tonumber(view.buffer) or 0)+1]
	assert(source,"O buffer da malha Draco nao foi carregado.")
	local offset=tonumber(view.byteOffset) or 0
	local length=tonumber(view.byteLength) or 0
	assert(length>0 and offset+length<=buffer.len(source),"O bloco Draco esta truncado no arquivo.")
	local decoded=Draco.decode(source,offset,length,yield)
	local mapped={indices=decoded.indices,attributes={}}
	for name,id in pairs(extension.attributes or {}) do
		local found=decoded.attributes[tonumber(id)]
		if found then mapped.attributes[name]=found end
	end
	cache[index]=mapped
	return mapped
end

function Gltf.primitive(doc,entry,matrix,scale,flip,options)
	local attributes=entry.attributes
	if type(attributes)~="table" or attributes.POSITION==nil then return nil,"atributos" end
	local mode=tonumber(entry.mode) or 4
	if mode~=4 and mode~=5 and mode~=6 then return nil,"modo" end
	local yield=options.yield
	local compressed
	if type(entry.extensions)=="table" and entry.extensions["KHR_draco_mesh_compression"]~=nil then
		local ok,result=pcall(Gltf.dracoMesh,doc,entry.extensions["KHR_draco_mesh_compression"],yield)
		if not ok then return nil,"draco",tostring(result) end
		compressed=result
	end
	local function fetch(accessor,name)
		if compressed then
			local found=compressed.attributes[name]
			if found then return found.values,found.components,found.count,true end
			return nil
		end
		if accessor==nil or Accessors.dataless(doc,accessor) then return nil end
		return Accessors.read(doc,accessor,yield)
	end
	local positions,positionWidth,count,filled=fetch(attributes.POSITION,"POSITION")
	if not positions then return nil,"vazio" end
	if positionWidth<3 or count<3 then return nil,"atributos" end
	if not filled then return nil,"vazio" end
	local uvs,uvWidth=fetch(attributes.TEXCOORD_0,"TEXCOORD_0")
	local colors,colorWidth=fetch(attributes.COLOR_0,"COLOR_0")
	local normals,normalWidth=fetch(attributes.NORMAL,"NORMAL")
	if normals and (normalWidth or 0)<3 then normals=nil end
	 
	local joints,jointWidth,weights,weightWidth
	if options.skin~=nil then
		joints,jointWidth=fetch(attributes.JOINTS_0,"JOINTS_0")
		weights,weightWidth=fetch(attributes.WEIGHTS_0,"WEIGHTS_0")
		if not (joints and weights and (jointWidth or 0)>=1 and (weightWidth or 0)>=1) then joints,weights=nil,nil end
	end
	local soup={positions=table.create(count),triangles={}}
	if uvs then soup.uvs=table.create(count) end
	if colors then soup.colors=table.create(count) end
	if normals then soup.normals=table.create(count) end
	if joints then
		soup.joints=table.create(count*4,0)
		soup.weights=table.create(count*4,0)
		soup.skin=options.skin
	end
	local bad={}
	local invalid=0
	local spread=0
	local anchor
	for i=0,count-1 do
		local slot=i*positionWidth
		local x,y,z=positions[slot+1],positions[slot+2],positions[slot+3]
		local point
		if finiteNumber(x) and finiteNumber(y) and finiteNumber(z) then
			point=Nodes.point(matrix,x,y,z)*scale
			if not (finiteNumber(point.X) and finiteNumber(point.Y) and finiteNumber(point.Z)) then point=nil end
		end
		if point then
			soup.positions[i+1]=point
			if anchor then
				local distance=(point-anchor).Magnitude
				if distance>spread then spread=distance end
			else
				anchor=point
			end
		else
			soup.positions[i+1]=Vector3.zero
			bad[i+1]=true
			invalid+=1
		end
		if uvs then
			local at=i*uvWidth
			local u,v=uvs[at+1],uvs[at+2]
			soup.uvs[i+1]=Vector2.new(finiteNumber(u) and u or 0,finiteNumber(v) and v or 0)
		end
		if colors then
			local at=i*colorWidth
			soup.colors[i+1]=Color3.new(math.clamp(colors[at+1] or 1,0,1),math.clamp(colors[at+2] or 1,0,1),math.clamp(colors[at+3] or 1,0,1))
		end
		if normals then
			local at=i*normalWidth
			local nx,ny,nz=normals[at+1],normals[at+2],normals[at+3]
			local direction=Nodes.direction(matrix,finiteNumber(nx) and nx or 0,finiteNumber(ny) and ny or 0,finiteNumber(nz) and nz or 0)
			soup.normals[i+1]=direction.Magnitude>1e-6 and direction.Unit or Vector3.zero
		end
		if joints then
			local jat,wat,base=i*jointWidth,i*weightWidth,i*4
			for k=0,3 do
				local joint=k<jointWidth and joints[jat+k+1] or 0
				local weight=k<weightWidth and weights[wat+k+1] or 0
				soup.joints[base+k+1]=finiteNumber(joint) and math.floor(joint+0.5) or 0
				soup.weights[base+k+1]=(finiteNumber(weight) and weight>0) and weight or 0
			end
		end
		if yield and i>0 and i%20000==0 then yield() end
	end
	if invalid>=count or spread<=0 then return nil,"vazio" end
	soup.invalid=invalid
	soup.spread=spread
	local indices
	if compressed then
		indices=compressed.indices
		if type(indices)~="table" or #indices<3 then return nil,"indices" end
	elseif entry.indices~=nil then
		if Accessors.dataless(doc,entry.indices) then return nil,"vazio" end
		local values,indexWidth,indexCount,indexFilled=Accessors.read(doc,entry.indices,yield)
		if not indexFilled or indexWidth~=1 or indexCount<3 then return nil,"indices" end
		indices=values
	else
		indices=table.create(count)
		for i=1,count do indices[i]=i-1 end
	end
	local triangles=soup.triangles
	local function push(a,b,c)
		if not (finiteNumber(a) and finiteNumber(b) and finiteNumber(c)) then return end
		a,b,c=math.floor(a+0.5)+1,math.floor(b+0.5)+1,math.floor(c+0.5)+1
		if a<1 or b<1 or c<1 or a>count or b>count or c>count then return end
		if a==b or b==c or a==c then return end
		if bad[a] or bad[b] or bad[c] then return end
		if flip then a,c=c,a end
		triangles[#triangles+1]={a,b,c}
	end
	if mode==4 then
		for i=1,#indices-2,3 do push(indices[i],indices[i+1],indices[i+2]) end
	elseif mode==5 then
		for i=1,#indices-2 do
			if i%2==1 then push(indices[i],indices[i+1],indices[i+2]) else push(indices[i+1],indices[i],indices[i+2]) end
		end
	else
		for i=2,#indices-1 do push(indices[1],indices[i],indices[i+1]) end
	end
	if #triangles==0 then return nil,"degenerado" end
	local info=Gltf.materialInfo(doc,entry.material)
	soup.color=info.color
	soup.alpha=info.alpha
	soup.doubleSided=info.doubleSided
	soup.alphaMode=info.alphaMode
	soup.material=entry.material
	soup.maps=Gltf.materialMaps(doc,entry.material)
	soup.texture=soup.maps and soup.maps.baseColor or nil
	return soup
end

function Gltf.build(doc,options)
	options=options or {}
	local scale=tonumber(options.scale) or 1
	assert(finiteNumber(scale) and scale>0 and scale<1e6,"Escala de importacao invalida.")
	local yield=options.yield
	local blocked=Gltf.unsupported(doc.json)
	assert(#blocked==0,"Este arquivo exige "..table.concat(blocked," e ")..", que o importador nao le. No Sketchfab baixe o formato glTF sem compressao, ou reexporte no Blender com a opcao Draco desmarcada, e importe de novo.")
	 
	 
	local joints=options.joints
	local placements=Nodes.placements(doc.json,nil,joints)
	if #placements==0 then
		for index=1,#doc.json.meshes do placements[#placements+1]={mesh=index-1,matrix=Nodes.identity(),node=nil} end
	end
	local materials=doc.json.materials or {}
	local soups={}
	local skipped=0
	local report={meshes=0,primitives=0,draco=0,empty=0,modes=0,indices=0,degenerate=0,attributes=0,invalid=0,triangles=0,skinned=0,rigid=0}
	for pi,placement in ipairs(placements) do
		local mesh=doc.json.meshes[placement.mesh+1]
		if type(mesh)=="table" and type(mesh.primitives)=="table" then
			report.meshes+=1
			local skinned=joints~=nil and placement.skin~=nil
			local matrix=skinned and Nodes.identity() or placement.matrix
			local flip=(not skinned) and Nodes.determinant(placement.matrix)<0
			for prIndex,entry in ipairs(mesh.primitives) do
				report.primitives+=1
				local soup,reason,detail=Gltf.primitive(doc,entry,matrix,scale,flip,{yield=yield,skin=skinned and placement.skin or nil})
				if soup then
					soup.name=placement.name or mesh.name or ("Malha "..tostring(placement.mesh+1))
					soup.nodeName=placement.name
					soup.meshName=mesh.name
					soup.node=placement.node
					soup.placement=pi
					soup.mesh=placement.mesh
					soup.primitive=prIndex
					local material=entry.material~=nil and materials[entry.material+1] or nil
					soup.materialName=type(material)=="table" and material.name or nil
					if soup.joints then
						report.skinned+=1
					elseif joints and placement.joint~=nil then
						soup.rigidJoint=placement.joint
						report.rigid+=1
					end
					report.triangles+=#soup.triangles
					report.invalid+=soup.invalid or 0
					soups[#soups+1]=soup
				else
					skipped+=1
					if reason=="draco" then
						report.draco+=1
						report.dracoError=report.dracoError or detail
					elseif reason=="vazio" then
						report.empty+=1
					elseif reason=="modo" then
						report.modes+=1
					elseif reason=="indices" then
						report.indices+=1
					elseif reason=="degenerado" then
						report.degenerate+=1
					else
						report.attributes+=1
					end
				end
				if yield then yield() end
			end
		end
	end
	if #soups==0 then
		if report.draco>0 then error("Nao foi possivel abrir as malhas Draco deste arquivo. "..tostring(report.dracoError or "Motivo desconhecido.").." Por enquanto, no Sketchfab baixe o glTF sem compressao ou reexporte no Blender com Draco desmarcado.",0) end
		if report.empty>0 then error("Os vertices vieram vazios em "..report.empty.." primitiva(s) do arquivo. Isso acontece com malhas compactadas ou com .gltf sem o .bin ao lado: envie tambem o .bin ou use o .glb sem compressao.",0) end
		if report.modes>0 and report.modes==report.primitives then error("O arquivo so tem pontos ou linhas, sem faces. Exporte o modelo triangulado.",0) end
		if report.indices>0 then error("Os indices de face estao ilegiveis em "..report.indices.." primitiva(s). Reexporte o modelo triangulado.",0) end
		if report.degenerate>0 then error(report.degenerate.." primitiva(s) do arquivo sairam sem nenhum triangulo valido. Reexporte o modelo triangulado e sem malhas vazias.",0) end
		error("Nenhuma malha triangular encontrada no arquivo. Exporte o modelo triangulado.",0)
	end
	return soups,skipped,report
end

local function accessorCount(doc,index)
	if type(index)~="number" then return nil end
	local entry=doc.json.accessors and doc.json.accessors[index+1]
	return type(entry)=="table" and tonumber(entry.count) or nil
end

 
 
function Gltf.outline(doc)
	local json=doc.json
	local materials=json.materials or {}
	local out={nodes={},meshes=#(json.meshes or {}),materials={},skins={},images=#(json.images or {}),textures=#(json.textures or {}),animations={},extensionsUsed=json.extensionsUsed or {},extensionsRequired=json.extensionsRequired or {},triangles=0,vertices=0,primitives=0,generator=type(json.asset)=="table" and json.asset.generator or nil}
	local placements=Nodes.placements(json)
	if #placements==0 then
		for index=1,#(json.meshes or {}) do placements[#placements+1]={mesh=index-1,matrix=Nodes.identity()} end
	end
	for _,placement in ipairs(placements) do
		local mesh=json.meshes[placement.mesh+1]
		if type(mesh)=="table" then
			local entry={node=placement.node,name=placement.name,mesh=placement.mesh,meshName=mesh.name,skin=placement.skin,primitives={},triangles=0,vertices=0}
			for _,primitive in ipairs(mesh.primitives or {}) do
				local attributes=type(primitive.attributes)=="table" and primitive.attributes or {}
				local vertices=accessorCount(doc,attributes.POSITION) or 0
				local mode=tonumber(primitive.mode) or 4
				local indexCount=accessorCount(doc,primitive.indices) or vertices
				local triangles=0
				if mode==4 then triangles=indexCount//3 elseif mode==5 or mode==6 then triangles=math.max(indexCount-2,0) end
				local material=primitive.material~=nil and materials[primitive.material+1] or nil
				local maps=Gltf.materialMaps(doc,primitive.material)
				entry.primitives[#entry.primitives+1]={material=primitive.material,materialName=type(material)=="table" and material.name or nil,triangles=triangles,vertices=vertices,mode=mode,texture=maps and maps.baseColor or nil,draco=type(primitive.extensions)=="table" and primitive.extensions["KHR_draco_mesh_compression"]~=nil,skinned=attributes.JOINTS_0~=nil and attributes.WEIGHTS_0~=nil,vertexColors=attributes.COLOR_0~=nil}
				entry.triangles+=triangles
				entry.vertices+=vertices
				out.primitives+=1
			end
			out.triangles+=entry.triangles
			out.vertices+=entry.vertices
			out.nodes[#out.nodes+1]=entry
		end
	end
	for index,material in ipairs(materials) do
		local maps=Gltf.materialMaps(doc,index-1)
		out.materials[index]={index=index-1,name=type(material)=="table" and material.name or nil,texture=maps and maps.baseColor or nil,doubleSided=type(material)=="table" and material.doubleSided==true,alphaMode=type(material)=="table" and material.alphaMode or "OPAQUE"}
	end
	for index,skin in ipairs(json.skins or {}) do
		local names={}
		for _,nodeIndex in ipairs(type(skin)=="table" and skin.joints or {}) do
			local node=json.nodes and json.nodes[nodeIndex+1]
			names[#names+1]=type(node)=="table" and node.name or ("Bone_"..tostring(nodeIndex))
		end
		out.skins[index]={index=index-1,name=type(skin)=="table" and skin.name or nil,joints=#names,jointNames=names}
	end
	for index,animation in ipairs(json.animations or {}) do
		out.animations[index]={index=index-1,name=type(animation)=="table" and animation.name or nil,channels=type(animation)=="table" and #(animation.channels or {}) or 0}
	end
	return out
end

return table.freeze(Gltf)
