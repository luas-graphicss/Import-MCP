local Limits=require(script.Parent.Limits)
local Codec=require(script.Parent.Codec)
local Partitioner=require(script.Parent.Partitioner)
local ImageBuild=require(script.Parent.ImageBuild)
local Materialize=require(script.Parent.Materialize)
local Yield=require(script.Parent.Yield)
local AssetService=game:GetService("AssetService")

local MeshBuild={}

local retained={}

local function bake(object,label,check)
	local ok,result,content=pcall(function() return AssetService:CreateDataModelContentAsync(Content.fromObject(object)) end)
	if check then check() end
	if ok and typeof(result)=="EnumItem" and result.Name=="Success" and typeof(content)=="Content" then
		return content,true
	end
	if ok and typeof(result)=="EnumItem" and result.Name~="Success" then
		error(label..": "..tostring(result).." / "..tostring(content),0)
	end
	return Content.fromObject(object),false
end

function MeshBuild.parts(root)
	if root:IsA("MeshPart") then return {root} end
	local parts={}
	for _,child in ipairs(root:GetChildren()) do
		if child:IsA("MeshPart") and child:GetAttribute("ImportMCP_Geometry")==true then parts[#parts+1]=child end
	end
	table.sort(parts,function(a,b) return (a:GetAttribute("ImportMCP_Chunk") or 1)<(b:GetAttribute("ImportMCP_Chunk") or 1) end)
	return parts
end

local function chunkCenter(group,ids)
	local low,high
	for _,id in ipairs(ids) do
		local position=Codec.readPosition(group,id)
		low=low and low:Min(position) or position
		high=high and high:Max(position) or position
	end
	return (low+high)*0.5
end

local function hasFlag(flags,flag)
	return (flags or 0)%(flag*2)>=flag
end

function MeshBuild.isSkinned(snapshot)
	if #(snapshot.bones or {})==0 then return false end
	for _,group in ipairs(snapshot.groups) do
		if hasFlag(group.flags,Codec.FLAG_SKIN) then return true end
	end
	return false
end

 
 
local SKINNING_METHODS={"AddBone","SetBoneName","SetBoneCFrame","SetBoneIsVirtual","SetBoneParent","SetVertexBones","SetVertexBoneWeights"}
local skinningCache
local function skinningApi(mesh)
	if skinningCache then return skinningCache end
	local api={}
	for _,name in ipairs(SKINNING_METHODS) do
		local ok,method=pcall(function() return mesh[name] end)
		api[name]=ok and type(method)=="function" and method or false
	end
	skinningCache=api
	return api
end

 
 
 
local function addMeshBone(mesh,name,cframe)
	local api=skinningApi(mesh)
	assert(api.AddBone and api.SetVertexBones and api.SetVertexBoneWeights,"Este Studio nao expoe EditableMesh:AddBone/SetVertexBones (skinning). Atualize o Roblox Studio ou importe com rig=false.")
	local ok,id=pcall(api.AddBone,mesh,{Name=name,CFrame=cframe,IsVirtual=false})
	if not ok or type(id)~="number" then
		ok,id=pcall(api.AddBone,mesh,{})
	end
	assert(ok and type(id)=="number","EditableMesh:AddBone falhou: "..tostring(id))
	if api.SetBoneName then pcall(api.SetBoneName,mesh,id,name) end
	if api.SetBoneCFrame then pcall(api.SetBoneCFrame,mesh,id,cframe) end
	if api.SetBoneIsVirtual then pcall(api.SetBoneIsVirtual,mesh,id,false) end
	return id
end

local function writeChunkBones(mesh,snapshot,group,cluster,center,rigOptions)
	local used={}
	for _,id in ipairs(cluster.vertices) do
		local bones=Codec.readSkin(group,id)
		if bones then
			for _,bone in ipairs(bones) do used[bone]=true end
		end
	end
	if rigOptions.boneTree then
		local changed=true
		while changed do
			changed=false
			for bone in pairs(used) do
				local parent=snapshot.bones[bone].parent
				if parent and not used[parent] then
					used[parent]=true
					changed=true
				end
			end
		end
	end
	local order={}
	for bone in pairs(used) do order[#order+1]=bone end
	table.sort(order)
	local local_ids={}
	local toLocal=CFrame.new(-center)
	for _,bone in ipairs(order) do
		local info=snapshot.bones[bone]
		local_ids[bone]=addMeshBone(mesh,info.name,toLocal*info.cframe)
	end
	local setParent=skinningApi(mesh).SetBoneParent
	if rigOptions.boneTree and setParent then
		for _,bone in ipairs(order) do
			local parent=snapshot.bones[bone].parent
			if parent and local_ids[parent] then pcall(setParent,mesh,local_ids[bone],local_ids[parent]) end
		end
	end
	return local_ids,#order
end

local function writeVertexSkin(mesh,group,id,vertexId,localIds)
	local bones,weights=Codec.readSkin(group,id)
	if not bones or #bones==0 then return false end
	local ids,values={},{}
	for k,bone in ipairs(bones) do
		local localId=localIds[bone]
		if localId then
			ids[#ids+1]=localId
			values[#values+1]=weights[k]
		end
	end
	local api=skinningApi(mesh)
	if #ids==0 or not api.SetVertexBones or not api.SetVertexBoneWeights then return false end
	local ok=pcall(api.SetVertexBones,mesh,vertexId,ids)
	if ok then ok=pcall(api.SetVertexBoneWeights,mesh,vertexId,values) end
	return ok
end

 
local function buildSkeleton(model,snapshot,meta,rigOptions)
	local controller=rigOptions.controller or "AnimationController"
	local rootName=rigOptions.rootName or "RootPart"
	if controller=="Humanoid" and rootName=="RootPart" then rootName="HumanoidRootPart" end
	local root=Instance.new("Part")
	root.Name=rootName
	local size=rigOptions.rootSize
	if type(size)=="table" then
		root.Size=Vector3.new(tonumber(size.x or size[1]) or 1,tonumber(size.y or size[2]) or 1,tonumber(size.z or size[3]) or 1)
	else
		root.Size=Vector3.new(1,1,1)
	end
	root.Transparency=1
	root.CanCollide=false
	root.CanQuery=false
	root.CanTouch=false
	root.CastShadow=false
	root.Anchored=meta.anchored~=false
	root.Massless=false
	local rootCFrame=CFrame.new()
	if rigOptions.rootAt=="bone" and snapshot.bones[1] then rootCFrame=CFrame.new(snapshot.bones[1].cframe.Position) end
	root.CFrame=rootCFrame
	root:SetAttribute("ImportMCP_Root",true)
	root.Parent=model
	model.PrimaryPart=root
	local instances={}
	for index,info in ipairs(snapshot.bones) do
		local bone=Instance.new("Bone")
		bone.Name=info.name
		local parentCFrame=info.parent and snapshot.bones[info.parent].cframe or rootCFrame
		bone.CFrame=parentCFrame:Inverse()*info.cframe
		bone.Parent=info.parent and instances[info.parent] or root
		instances[index]=bone
	end
	if controller=="Humanoid" then
		local humanoid=Instance.new("Humanoid")
		humanoid.Parent=model
		local animator=Instance.new("Animator")
		animator.Parent=humanoid
	elseif controller~="none" then
		local animationController=Instance.new("AnimationController")
		animationController.Parent=model
		local animator=Instance.new("Animator")
		animator.Parent=animationController
	end
	return root
end

 
 
 
function MeshBuild.build(snapshot,options)
	options=options or {}
	local meta=snapshot.meta
	local function check()
		if options.check then options.check() end
	end
	local yield=options.yield or Yield.ticker(options.check)
	local function stage(name)
		if options.stage then options.stage(name) end
	end
	check()
	local model=Instance.new("Model")
	model.Name=options.name or meta.name
	model.WorldPivot=CFrame.new()
	local mesh,loosePart
	local state={mode=options.mode=="asset" and "asset" or "session",fallback=nil,assetIds={}}
	local report={chunks=0,triangles=0,vertices=0,textures=0,dropped=0,bones=0,skinnedVertices=0,skinned=false}
	local skinned=MeshBuild.isSkinned(snapshot)
	local rigOptions=type(meta.rig)=="table" and meta.rig or {}
	local root

	local function canFallback()
		return options.fallback~=false and #state.assetIds==0
	end

	local function uploadOrBake(object,label,assetName)
		if state.mode=="asset" then
			stage("enviando")
			local ok,result=pcall(Materialize.upload,object,Enum.AssetType.Mesh,assetName,{check=check})
			if ok then
				object:Destroy()
				state.assetIds[#state.assetIds+1]=result
				return result,"asset"
			end
			if not (canFallback() and Materialize.isFallbackError(result)) then
				error(Materialize.errorText(result),0)
			end
			state.mode="session"
			state.fallback=Materialize.errorText(result)
			stage("construindo")
		end
		local content,baked=bake(object,label,check)
		if baked then object:Destroy() else retained[#retained+1]=object end
		return content,"session"
	end

	local ok,err=xpcall(function()
		local contents={}
		for index,texture in ipairs(snapshot.textures) do
			local content,info=ImageBuild.fromBytes(texture.bytes,{yield=yield,check=check,stage=options.stage,mode=state.mode,fallback=canFallback(),name=string.format("%s tex%d",model.Name,index)})
			if info.mode=="asset" then
				state.assetIds[#state.assetIds+1]=info.assetId
			elseif state.mode=="asset" then
				state.mode="session"
				state.fallback=info.fallback
			end
			contents[index]=content
			report.textures+=1
			check()
		end
		stage("construindo")
		if skinned then
			report.skinned=true
			report.bones=#snapshot.bones
			 
			if options.skeleton~=false then root=buildSkeleton(model,snapshot,meta,rigOptions) end
		end
		local chunkIndex=0
		local singleChunk=#snapshot.groups==1
		for gi,group in ipairs(snapshot.groups) do
			local plan=Partitioner.split(group.vertexCount,group.triangleCount,function(ti) return Codec.readTriangle(group,ti) end,{yieldFn=yield})
			if #plan>1 then singleChunk=false end
			local groupSkinned=skinned and hasFlag(group.flags,Codec.FLAG_SKIN)
			local groupColors=hasFlag(group.flags,Codec.FLAG_COLORS)
			for ci,cluster in ipairs(plan) do
				check()
				chunkIndex+=1
				mesh=AssetService:CreateEditableMesh()
				assert(mesh,"EditableMesh indisponivel na submalha "..chunkIndex..".")
				local center=chunkCenter(group,cluster.vertices)
				local localBones,boneCount
				if groupSkinned then
					localBones,boneCount=writeChunkBones(mesh,snapshot,group,cluster,center,rigOptions)
				end
				local ids,uvIds,normalIds,colorIds={},{},{},nil
				if groupColors then colorIds={} end
				for n,id in ipairs(cluster.vertices) do
					local position,normal,uv=Codec.readVertex(group,id)
					local vertexId=mesh:AddVertex(position-center)
					ids[id]=vertexId
					uvIds[id]=mesh:AddUV(uv)
					normalIds[id]=normal.Magnitude>=0.5 and mesh:AddNormal(normal.Unit) or false
					if groupColors then
						local color,alpha=Codec.readColor(group,id)
						local colorId=mesh:AddColor(color,alpha)
						colorIds[id]=colorId
					end
					if groupSkinned and writeVertexSkin(mesh,group,id,vertexId,localBones) then report.skinnedVertices+=1 end
					if n%Limits.YIELD_EVERY==0 then yield() end
				end
				local added=0
				for n,ti in ipairs(cluster.triangles) do
					local a,b,c=Codec.readTriangle(group,ti)
					local faceOk,face=pcall(mesh.AddTriangle,mesh,ids[a],ids[b],ids[c])
					if faceOk and face then
						added+=1
						mesh:SetFaceUVs(face,{uvIds[a],uvIds[b],uvIds[c]})
						if normalIds[a] and normalIds[b] and normalIds[c] then
							mesh:SetFaceNormals(face,{normalIds[a],normalIds[b],normalIds[c]})
						end
						if colorIds then pcall(mesh.SetFaceColors,mesh,face,{colorIds[a],colorIds[b],colorIds[c]}) end
					else
						report.dropped+=1
					end
					if n%Limits.YIELD_EVERY==0 then yield() end
				end
				assert(added>0,"Submalha "..chunkIndex.." sem triangulos validos.")
				local collision=options.collisionByChunk and options.collisionByChunk[chunkIndex] or meta.collision
				local fidelity={CollisionFidelity=Enum.CollisionFidelity[collision],RenderFidelity=Enum.RenderFidelity.Precise}
				local assetName=string.format("%s_%02d_%03d",model.Name,gi,ci)
				local contentOrId,used=uploadOrBake(mesh,"Conversao da submalha "..chunkIndex,assetName)
				mesh=nil
				if used=="asset" then
					loosePart=Materialize.meshPart(contentOrId,fidelity,check)
				else
					loosePart=AssetService:CreateMeshPartAsync(contentOrId,fidelity)
				end
				check()
				assert(loosePart,"CreateMeshPartAsync nao retornou a submalha "..chunkIndex..".")
				local part=loosePart
				if singleChunk and not skinned then
					part.Name=model.Name
				elseif #plan==1 then
					part.Name=group.name
				else
					part.Name=string.format("%s_%03d",group.name,ci)
				end
				part.Anchored=(not skinned) and meta.anchored~=false
				part.CanCollide=meta.canCollide~=false
				part.CanQuery=true
				part.CanTouch=true
				part.CastShadow=true
				part.Color=group.color
				part.Transparency=group.transparency
				part.Material=Enum.Material.SmoothPlastic
				part.DoubleSided=group.doubleSided or meta.doubleSided==true
				local size=part.MeshSize
				part.Size=Vector3.new(math.max(size.X,0.001),math.max(size.Y,0.001),math.max(size.Z,0.001))
				part.CFrame=CFrame.new(center)
				if group.texture and contents[group.texture] then part.TextureContent=contents[group.texture] end
				part:SetAttribute("ImportMCP_Geometry",true)
				part:SetAttribute("ImportMCP_Chunk",chunkIndex)
				part:SetAttribute("ImportMCP_Group",gi)
				part:SetAttribute("ImportMCP_GroupName",group.name)
				part:SetAttribute("ImportMCP_Triangles",added)
				part:SetAttribute("ImportMCP_Vertices",#cluster.vertices)
				if groupSkinned then part:SetAttribute("ImportMCP_Bones",boneCount or 0) end
				part.Parent=model
				if skinned and root then
					local weld=Instance.new("WeldConstraint")
					weld.Name="RootWeld"
					weld.Part0=root
					weld.Part1=part
					weld.Parent=part
				end
				loosePart=nil
				report.chunks+=1
				report.triangles+=added
				report.vertices+=#cluster.vertices
			end
		end
		check()
		model:SetAttribute("ImportMCP_Chunks",chunkIndex)
		if skinned then
			model:SetAttribute("ImportMCP_Skinned",true)
			model:SetAttribute("ImportMCP_Bones",#snapshot.bones)
		end
	end,debug.traceback)
	if mesh then mesh:Destroy() end
	if not ok then
		if loosePart then loosePart:Destroy() end
		model:Destroy()
		error("ImportMCP: reconstrucao cancelada sem inserir geometria parcial. Confira Mesh/Image APIs, o beta CreateAssetAsync e memoria. "..tostring(err),0)
	end
	report.mode=state.mode
	report.assetIds=state.assetIds
	report.fallback=state.fallback
	return model,report
end

 
function MeshBuild.unwrap(model)
	if model:GetAttribute("ImportMCP_Skinned")==true then return model end
	local parts=MeshBuild.parts(model)
	if #parts==1 then
		local part=parts[1]
		for _,child in ipairs(model:GetChildren()) do
			if child~=part then child.Parent=part end
		end
		for name,value in pairs(model:GetAttributes()) do part:SetAttribute(name,value) end
		part.Parent=nil
		model:Destroy()
		return part
	end
	return model
end

return table.freeze(MeshBuild)
