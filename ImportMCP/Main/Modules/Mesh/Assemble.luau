local Runtime=script.Parent.Parent.Runtime
local Codec=require(Runtime.Codec)
local ImageDecode=require(Runtime.ImageDecode)
local Limits=require(Runtime.Limits)
local Gltf=require(script.Parent.Gltf)
local Layout=require(script.Parent.Layout)
local Rig=require(script.Parent.Rig)

local Assemble={}

local WHITE=Color3.new(1,1,1)

local function colorKey(color)
	color=color or WHITE
	return string.format("%d|%d|%d",math.round(color.R*255),math.round(color.G*255),math.round(color.B*255))
end

local function computeNormals(positions,triangles,yield)
	local normals=table.create(#positions,Vector3.zero)
	for index,triangle in ipairs(triangles) do
		local pa,pb,pc=positions[triangle[1]],positions[triangle[2]],positions[triangle[3]]
		if pa and pb and pc then
			local normal=(pb-pa):Cross(pc-pa)
			normals[triangle[1]]=normals[triangle[1]]+normal
			normals[triangle[2]]=normals[triangle[2]]+normal
			normals[triangle[3]]=normals[triangle[3]]+normal
		end
		if index%Limits.YIELD_EVERY==0 then yield() end
	end
	for index,normal in ipairs(normals) do
		normals[index]=normal.Magnitude>1e-9 and normal.Unit or Vector3.zero
		if index%Limits.YIELD_EVERY==0 then yield() end
	end
	return normals
end

 
 
function Assemble.build(soups,doc,options)
	options=options or {}
	local yield=options.yield or function() end
	assert(type(soups)=="table" and #soups>0,"Nada para montar.")
	local report={groups=0,vertices=0,triangles=0,dropped=0,textures=0,skippedTextures=0,notes={},skinnedVertices=0,rigidVertices=0,unweightedVertices=0}
	local textures={}
	local textureIndex={}
	local function resolveTexture(imageIndex)
		if imageIndex==nil then return nil end
		local cached=textureIndex[imageIndex]
		if cached~=nil then return cached or nil end
		local bytes=doc and Gltf.imageBytes(doc,imageIndex,yield)
		local kind=bytes and ImageDecode.kind(bytes)
		if bytes and kind and buffer.len(bytes)<=Limits.MAX_IMAGE_BYTES then
			textures[#textures+1]={format=kind,bytes=bytes}
			textureIndex[imageIndex]=#textures
			report.textures+=1
			return #textures
		end
		textureIndex[imageIndex]=false
		report.skippedTextures+=1
		report.notes[#report.notes+1]=bytes and ("Textura "..imageIndex.." em formato nao suportado; use PNG ou JPEG embutido.") or ("Textura "..imageIndex.." nao encontrada no arquivo.")
		return nil
	end
	local rig=options.rig
	local layout=options.layout or Layout.options(nil,options.name)
	local items={}
	for index,soup in ipairs(soups) do
		local texture=resolveTexture(soup.texture)
		items[index]={
			index=index,
			node=soup.placement,
			nodeName=soup.nodeName,
			mesh=soup.mesh,
			meshName=soup.meshName,
			material=soup.material,
			materialName=soup.materialName,
			texture=texture,
			colorKey=colorKey(soup.color),
			alpha=soup.alpha or 1,
			doubleSided=soup.doubleSided==true,
			triangles=#soup.triangles,
			vertices=#soup.positions,
			skinned=rig~=nil and (soup.joints~=nil or soup.rigidJoint~=nil),
			hasVertexColors=soup.colors~=nil,
		}
		yield()
	end
	local plan=Layout.plan(items,layout)
	for _,note in ipairs(plan.notes) do report.notes[#report.notes+1]=note end
	local useRig=false
	if rig then
		for _,planned in ipairs(plan.groups) do
			if planned.skinned then useRig=true break end
		end
	end
	local firstBone=1
	local groups={}
	for _,planned in ipairs(plan.groups) do
		local first=soups[planned.items[1].index]
		local group={
			name=planned.name,
			texture=planned.texture,
			color=planned.colors and WHITE or (first.color or WHITE),
			transparency=planned.transparency or 0,
			doubleSided=planned.doubleSided==true,
			colors=planned.colors==true,
			skinned=useRig,
			sources=planned.sources,
			positions={},normals={},uvs={},triangles={},
		}
		if group.colors then group.vertexColors={} group.vertexAlphas={} end
		if group.skinned then group.bones={} group.weights={} end
		for _,item in ipairs(planned.items) do
			local soup=soups[item.index]
			local base=#group.positions
			local positions=soup.positions
			local normals=soup.normals or computeNormals(positions,soup.triangles,yield)
			local uvs=soup.uvs
			local skinMap=soup.skin~=nil and rig and rig.skins[soup.skin] or nil
			local rigidBone=soup.rigidJoint~=nil and rig and rig.byNode[soup.rigidJoint] or nil
			local fallbackBone=(skinMap and skinMap.root) or rigidBone or firstBone
			for index,position in ipairs(positions) do
				group.positions[base+index]=position
				group.normals[base+index]=normals[index] or Vector3.zero
				group.uvs[base+index]=uvs and uvs[index] or Vector2.zero
				if group.colors then
					group.vertexColors[base+index]=soup.colors and soup.colors[index] or soup.color or WHITE
					group.vertexAlphas[base+index]=soup.alpha or 1
				end
				if group.skinned then
					local bones,weights={},{}
					if soup.joints and skinMap then
						local at=(index-1)*4
						for k=1,4 do
							local weight=soup.weights[at+k]
							local bone=skinMap.joints[(soup.joints[at+k] or 0)+1]
							if bone and weight and weight>0 then
								bones[#bones+1]=bone
								weights[#weights+1]=weight
							end
						end
						if #bones>0 then report.skinnedVertices+=1 end
					elseif rigidBone then
						bones[1]=rigidBone
						weights[1]=1
						report.rigidVertices+=1
					end
					if #bones==0 then
						bones[1]=fallbackBone
						weights[1]=1
						report.unweightedVertices+=1
					end
					group.bones[base+index]=bones
					group.weights[base+index]=weights
				end
				if index%Limits.YIELD_EVERY==0 then yield() end
			end
			for index,triangle in ipairs(soup.triangles) do
				local pa,pb,pc=positions[triangle[1]],positions[triangle[2]],positions[triangle[3]]
				if pa and pb and pc and (pb-pa):Cross(pc-pa).Magnitude>1e-12 then
					group.triangles[#group.triangles+1]={triangle[1]+base,triangle[2]+base,triangle[3]+base}
				else
					report.dropped+=1
				end
				if index%Limits.YIELD_EVERY==0 then yield() end
			end
			yield()
		end
		groups[#groups+1]=group
	end
	if useRig and report.unweightedVertices>0 then
		report.notes[#report.notes+1]=report.unweightedVertices.." vertice(s) sem peso de osso foram presos ao osso raiz para nao colapsarem na origem."
	end
	local low,high
	for _,group in ipairs(groups) do
		for index,position in ipairs(group.positions) do
			low=low and low:Min(position) or position
			high=high and high:Max(position) or position
			if index%Limits.YIELD_EVERY==0 then yield() end
		end
	end
	assert(low and high,"Modelo sem vertices.")
	local offset=Vector3.zero
	if options.center~=false then offset=Vector3.new(-(low.X+high.X)/2,0,-(low.Z+high.Z)/2) end
	if options.ground~=false then offset=offset+Vector3.new(0,-low.Y,0) end
	if options.centerY then offset=Vector3.new(offset.X,-(low.Y+high.Y)/2,offset.Z) end
	local snapshot={groups={},textures=textures,bones={}}
	for _,group in ipairs(groups) do
		if #group.triangles>0 then
			local remap={}
			local count=0
			for _,triangle in ipairs(group.triangles) do
				for corner=1,3 do
					local vertex=triangle[corner]
					if not remap[vertex] then
						count+=1
						remap[vertex]=count
					end
				end
			end
			local flags=(group.colors and Codec.FLAG_COLORS or 0)+(group.skinned and Codec.FLAG_SKIN or 0)
			local stride=Codec.stride(flags)
			local vertexData=buffer.create(count*stride)
			local indexData=buffer.create(#group.triangles*Codec.INDEX_STRIDE)
			for vertex=1,#group.positions do
				local target=remap[vertex]
				if target then
					Codec.writeVertex(vertexData,target,group.positions[vertex]+offset,group.normals[vertex],group.uvs[vertex],stride)
					if group.colors then Codec.writeColor(vertexData,target,stride,group.vertexColors[vertex],group.vertexAlphas[vertex]) end
					if group.skinned then Codec.writeSkin(vertexData,target,stride,flags,group.bones[vertex],group.weights[vertex]) end
				end
				if vertex%Limits.YIELD_EVERY==0 then yield() end
			end
			for index,triangle in ipairs(group.triangles) do
				Codec.writeTriangle(indexData,index,remap[triangle[1]],remap[triangle[2]],remap[triangle[3]])
				if index%Limits.YIELD_EVERY==0 then yield() end
			end
			snapshot.groups[#snapshot.groups+1]={name=group.name,vertexCount=count,triangleCount=#group.triangles,texture=group.texture,color=group.color,transparency=group.transparency,doubleSided=group.doubleSided,flags=flags,vertexData=vertexData,indexData=indexData,sources=group.sources}
			report.groups+=1
			report.vertices+=count
			report.triangles+=#group.triangles
		else
			report.notes[#report.notes+1]="'"..group.name.."' ficou sem triangulos validos e foi omitido."
		end
	end
	assert(#snapshot.groups>0,"Todos os triangulos do modelo sairam degenerados.")
	local boneNames=nil
	if useRig then
		local cframes=Rig.cframes(rig,options.scale or 1,offset)
		for index,bone in ipairs(rig.bones) do
			snapshot.bones[index]={name=bone.name or bone.raw,parent=bone.parent,cframe=cframes[index]}
		end
		snapshot.rig={rootName=rig.rootName or "RootPart",controller=rig.controller or "AnimationController",rootAt=rig.rootAt or "origin",rootSize=rig.rootSize}
		boneNames=Rig.names(rig)
	end
	report.layout=Layout.summary(plan,boneNames)
	report.bones=#snapshot.bones
	report.size=high-low
	return snapshot,report,plan
end

return table.freeze(Assemble)
