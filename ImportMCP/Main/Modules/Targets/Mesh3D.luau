local Runtime=script.Parent.Parent.Runtime
local Codec=require(Runtime.Codec)
local MeshBuild=require(Runtime.MeshBuild)
local Materialize=require(Runtime.Materialize)
local Mesh=script.Parent.Parent.Mesh
local Gltf=require(Mesh.Gltf)
local Assemble=require(Mesh.Assemble)
local Layout=require(Mesh.Layout)
local Rig=require(Mesh.Rig)
local Resolve=require(script.Parent.Resolve)
local Props=require(script.Parent.Props)
local Persist=require(script.Parent.Persist)
local HttpService=game:GetService("HttpService")

local Mesh3D={}

Mesh3D.classes={"Model","MeshPart"}

local function decodeJson(text)
	return HttpService:JSONDecode(text)
end

function Mesh3D.matches(bytes)
	if typeof(bytes)~="buffer" or buffer.len(bytes)<20 then return false end
	if buffer.readstring(bytes,0,4)=="glTF" then return true end
	local head=buffer.readstring(bytes,0,math.min(buffer.len(bytes),512)):gsub("^\239\187\191","")
	return head:match("^%s*{")~=nil and (head:find('"asset"',1,true) or head:find('"meshes"',1,true))~=nil
end

local function rigOptions(options)
	if options.rig==false or options.skinning==false or options.skinned==false then return nil end
	local rig=type(options.rig)=="table" and table.clone(options.rig) or {}
	if rig.enabled==false then return nil end
	if rig.rename==nil and type(options.bones)=="table" then rig.rename=options.bones end
	if rig.stripPrefix==nil and options.stripPrefix~=nil then rig.stripPrefix=options.stripPrefix end
	if rig.controller==nil and options.controller~=nil then rig.controller=options.controller end
	return rig
end

local function openDocument(job,ctx)
	assert(typeof(job.bytes)=="buffer","Bytes do modelo ausentes.")
	if ctx.stage then ctx.stage("analisando") end
	local doc=Gltf.parse(buffer.tostring(job.bytes),{decodeJson=decodeJson})
	Gltf.resolveBuffers(doc,{externals=job.externals or {},yield=ctx.yield})
	if ctx.check then ctx.check() end
	return doc
end

local function collectRig(doc,options,yield)
	local wanted=rigOptions(options)
	if not wanted then return nil,wanted end
	local rig=Rig.collect(doc,{yield=yield})
	if rig then Rig.apply(rig,wanted) end
	return rig,wanted
end

 
local function outlineItems(doc,outline,rig)
	local items={}
	for pi,entry in ipairs(outline.nodes) do
		for _,primitive in ipairs(entry.primitives) do
			local info=Gltf.materialInfo(doc,primitive.material)
			local color=info.color or Color3.new(1,1,1)
			items[#items+1]={
				index=#items+1,
				node=pi,
				nodeName=entry.name,
				mesh=entry.mesh,
				meshName=entry.meshName,
				material=primitive.material,
				materialName=primitive.materialName,
				texture=primitive.texture,
				colorKey=string.format("%d|%d|%d",math.round(color.R*255),math.round(color.G*255),math.round(color.B*255)),
				alpha=info.alpha or 1,
				doubleSided=info.doubleSided==true,
				triangles=primitive.triangles,
				vertices=primitive.vertices,
				skinned=rig~=nil and (entry.skin~=nil and primitive.skinned),
				hasVertexColors=primitive.vertexColors==true,
			}
		end
	end
	return items
end

 
function Mesh3D.inspect(job,ctx)
	ctx=ctx or {}
	local options=job.options or {}
	local doc=openDocument(job,ctx)
	local outline=Gltf.outline(doc)
	local rig=collectRig(doc,options,ctx.yield)
	local items=outlineItems(doc,outline,rig)
	local layout=Layout.options(options,job.name)
	local plan=Layout.plan(items,layout)
	local boneNames=rig and Rig.names(rig) or nil
	local problems=Layout.check(plan,boneNames,layout.expect)
	return {
		file=job.fileName,
		generator=outline.generator,
		nodes=outline.nodes,
		meshes=outline.meshes,
		primitives=outline.primitives,
		triangles=outline.triangles,
		vertices=outline.vertices,
		materials=outline.materials,
		images=outline.images,
		skins=outline.skins,
		animations=outline.animations,
		extensionsRequired=outline.extensionsRequired,
		unsupported=Gltf.unsupported(doc.json),
		rig=rig and Rig.describe(rig) or nil,
		layout=Layout.summary(plan,boneNames),
		problems=problems,
		ok=#problems==0,
	}
end

function Mesh3D.import(job,ctx)
	ctx=ctx or {}
	local yield=ctx.yield
	local target=job.target or {}
	local options=job.options or {}
	local mode=Materialize.mode(job.persist)
	local scale=tonumber(options.scale) or 1
	local doc=openDocument(job,ctx)
	local rig,rigWanted=collectRig(doc,options,yield)
	if ctx.stage then ctx.stage("montando") end
	local soups,skipped,gltfReport=Gltf.build(doc,{scale=scale,yield=yield,joints=rig and rig.joints or nil})
	local layout=Layout.options(options,job.name)
	local snapshot,report,plan=Assemble.build(soups,doc,{yield=yield,center=options.center,ground=options.ground,centerY=options.centerY,scale=scale,name=job.name,layout=layout,rig=rig})
	local boneNames=#snapshot.bones>0 and Rig.names(rig) or nil
	local problems=Layout.check(plan,boneNames,layout.expect)
	if #problems>0 and layout.strict~=false then
		local lines={}
		for _,part in ipairs(report.layout.parts) do
			lines[#lines+1]=string.format("%s (%d tri%s)",part.name,part.triangles,part.chunks>1 and (", "..part.chunks.." submalhas") or "")
		end
		error("Layout diferente do esperado: "..table.concat(problems,"; ")..". Layout atual ("..plan.split.."): "..table.concat(lines,", ")..". Use Api.plan/inspect para ajustar split, groups, rename ou expect; strict=false importa mesmo assim.",0)
	end
	local meta={name=tostring(job.name or "Modelo"):sub(1,100),kind="Mesh",collision=options.collision or "Default",doubleSided=options.doubleSided==true,anchored=options.anchored~=false,canCollide=options.canCollide~=false,source=job.fileName,scale=scale,split=plan.split,parts=#snapshot.groups}
	if snapshot.rig then
		meta.rig={rootName=snapshot.rig.rootName,controller=snapshot.rig.controller,rootAt=snapshot.rig.rootAt,rootSize=snapshot.rig.rootSize,boneTree=rigWanted and rigWanted.boneTree==true or false}
		meta.bones=#snapshot.bones
	end
	snapshot.meta=meta
	Codec.validate(snapshot,yield)
	if ctx.check then ctx.check() end
	if ctx.stage then ctx.stage("construindo") end
	local model,buildReport=MeshBuild.build(snapshot,{check=ctx.check,yield=yield,stage=ctx.stage,mode=mode,fallback=job.fallback~=false})
	local root=model
	local skinned=buildReport.skinned==true
	if (target.class or "Model")=="MeshPart" and not skinned then root=MeshBuild.unwrap(model) end
	local parent=Resolve.parent(target.parent,workspace)
	root.Name=Resolve.uniqueName(parent,job.name)
	local pivot=Props.position(target.cframe or target.position) or CFrame.new()
	if root:IsA("Model") then
		root.WorldPivot=CFrame.new()
		root:PivotTo(pivot)
	else
		root.CFrame=pivot*root.CFrame
	end
	local applied,failed=Props.apply(root,target.properties)
	root.Parent=parent
	local bytes=0
	local info={Source=job.fileName,Groups=#snapshot.groups,Triangles=report.triangles,Vertices=report.vertices,Scale=scale,Split=plan.split}
	if skinned then info.Bones=#snapshot.bones end
	local usedMode=buildReport.mode
	if usedMode=="asset" then
		Materialize.mark(root,"Mesh",buildReport.assetIds,info)
	elseif mode~=false then
		if ctx.stage then ctx.stage("persistindo") end
		local data=Codec.encode(snapshot,yield)
		bytes=buffer.len(data)
		Persist.attach(root,"Mesh",data,Codec.MAGIC,info,yield)
	else
		usedMode="none"
	end
	local parts={}
	for _,part in ipairs(MeshBuild.parts(root)) do
		parts[#parts+1]={name=part.Name,group=part:GetAttribute("ImportMCP_GroupName") or part.Name,triangles=part:GetAttribute("ImportMCP_Triangles"),vertices=part:GetAttribute("ImportMCP_Vertices"),bones=part:GetAttribute("ImportMCP_Bones")}
	end
	local notes=table.clone(report.notes)
	for _,problem in ipairs(problems) do notes[#notes+1]="expect: "..problem end
	if skinned and rigWanted and rigWanted.controller==nil then notes[#notes+1]="Rig importado com AnimationController+Animator; use rig.controller='Humanoid' para personagens jogaveis." end
	local size=report.size or Vector3.zero
	return root,{
		kind="Mesh",class=root.ClassName,groups=report.groups,chunks=buildReport.chunks,triangles=report.triangles,vertices=report.vertices,
		textures=report.textures,skippedTextures=report.skippedTextures,droppedTriangles=report.dropped+buildReport.dropped,skippedPrimitives=skipped,
		gltf=gltfReport,size={x=size.X,y=size.Y,z=size.Z},notes=notes,payloadBytes=bytes,propertiesApplied=applied,propertiesFailed=failed,
		persisted=usedMode~="none",mode=usedMode,requestedMode=mode or "none",assetIds=buildReport.assetIds,fallback=buildReport.fallback,
		requestedClass=target.class or "Model",layout=report.layout,parts=parts,expectProblems=problems,
		skinned=skinned,bones=skinned and Rig.names(rig) or nil,boneCount=#snapshot.bones,skinnedVertices=buildReport.skinnedVertices,
		rig=skinned and {rootName=root.PrimaryPart and root.PrimaryPart.Name or nil,controller=snapshot.rig and snapshot.rig.controller or nil,unweightedVertices=report.unweightedVertices,rigidVertices=report.rigidVertices} or nil,
	}
end

return table.freeze(Mesh3D)
