local Limits=require(script.Parent.Parent.Limits)
local Partitioner=require(script.Parent.Partitioner)
local AssetService=game:GetService("AssetService")

local Mesh={}

local WHITE=Color3.new(1,1,1)

local function bake(object,label,check)
	local result,content=AssetService:CreateDataModelContentAsync(Content.fromObject(object))
	if check then check() end
	assert(typeof(result)=="EnumItem" and result.Name=="Success" and typeof(content)=="Content",label..": "..tostring(result))
	return content
end

local function safeSize(size)
	return Vector3.new(math.max(size.X,0.001),math.max(size.Y,0.001),math.max(size.Z,0.001))
end

function Mesh.normals(soup,yield)
	local positions,triangles=soup.positions,soup.triangles
	local count=#positions
	local existing=soup.normals
	local complete=existing~=nil
	if existing then
		for i=1,count do
			if existing[i]==nil then complete=false break end
		end
		if complete then return existing end
	end
	local accumulated=table.create(count,Vector3.zero)
	for i,t in ipairs(triangles) do
		local a,b,c=positions[t[1]],positions[t[2]],positions[t[3]]
		local n=(b-a):Cross(c-a)
		accumulated[t[1]]+=n
		accumulated[t[2]]+=n
		accumulated[t[3]]+=n
		if yield and i%Limits.YIELD_EVERY==0 then yield() end
	end
	local out=table.create(count)
	for i=1,count do
		local given=existing and existing[i]
		if given then
			out[i]=given
		else
			local n=accumulated[i]
			out[i]=n.Magnitude>1e-9 and n.Unit or Vector3.yAxis
		end
	end
	soup.normals=out
	return out
end

function Mesh.bounds(soups)
	local lo,hi
	for _,soup in ipairs(soups) do
		for _,p in ipairs(soup.positions) do
			lo=lo and lo:Min(p) or p
			hi=hi and hi:Max(p) or p
		end
	end
	return lo,hi
end

function Mesh.center(soups,options)
	options=options or {}
	if options.center==false and not options.ground then return Vector3.zero end
	local lo,hi=Mesh.bounds(soups)
	if not lo then return Vector3.zero end
	local center=(lo+hi)*0.5
	local offset=Vector3.zero
	if options.center~=false then offset=Vector3.new(center.X,center.Y,center.Z) end
	if options.ground then offset=Vector3.new(offset.X,lo.Y,offset.Z) end
	if offset==Vector3.zero then return offset end
	for _,soup in ipairs(soups) do
		local positions=soup.positions
		for i=1,#positions do positions[i]=positions[i]-offset end
	end
	return offset
end

function Mesh.merge(soups,name,yield)
	if #soups==1 then
		soups[1].name=name or soups[1].name
		return soups[1]
	end
	local out={positions={},triangles={},uvs={},normals={},colors={},name=name or "Merged"}
	local best,bestCount=nil,-1
	local offset=0
	for _,soup in ipairs(soups) do
		Mesh.normals(soup,yield)
		local base=soup.color or WHITE
		for i,p in ipairs(soup.positions) do
			out.positions[offset+i]=p
			out.uvs[offset+i]=soup.uvs and soup.uvs[i] or Vector2.zero
			out.normals[offset+i]=soup.normals[i]
			out.colors[offset+i]=soup.colors and soup.colors[i] or base
		end
		for i,t in ipairs(soup.triangles) do
			out.triangles[#out.triangles+1]={t[1]+offset,t[2]+offset,t[3]+offset}
			if yield and i%Limits.YIELD_EVERY==0 then yield() end
		end
		if soup.textureContent and #soup.triangles>bestCount then
			best,bestCount=soup,#soup.triangles
		end
		offset+=#soup.positions
	end
	if best then
		out.textureContent=best.textureContent
		out.texture=best.texture
	end
	return out
end

function Mesh.build(soup,options)
	options=options or {}
	local yield=options.yield or function() end
	local check=options.check or function() end
	local positions,triangles=soup.positions,soup.triangles
	assert(#triangles>0,"Malha sem triangulos: "..tostring(soup.name))
	assert(#positions<=Limits.VERTICES and #triangles<=Limits.TRIANGLES,"Malha excede a capacidade suportada.")
	local normals=Mesh.normals(soup,yield)
	local plan=Partitioner.split(#positions,#triangles,function(ti)
		local t=triangles[ti]
		return t[1],t[2],t[3]
	end,{yieldFn=yield})
	local collision=Enum.CollisionFidelity[options.collision or "Default"] or Enum.CollisionFidelity.Default
	local baseColor=soup.color or WHITE
	local parts={}
	local editable
	local ok,err=xpcall(function()
		for ci,cluster in ipairs(plan) do
			check()
			editable=AssetService:CreateEditableMesh()
			assert(editable,"EditableMesh indisponivel; confira memoria e permissao de Mesh/Image APIs.")
			local center=Partitioner.bounds(positions,cluster.vertices)
			local vertexIds,normalIds,uvIds,colorIds={},{},{},{}
			for _,id in ipairs(cluster.vertices) do
				vertexIds[id]=editable:AddVertex(positions[id]-center)
				normalIds[id]=editable:AddNormal(normals[id])
				uvIds[id]=editable:AddUV(soup.uvs and soup.uvs[id] or Vector2.zero)
				if soup.colors then colorIds[id]=editable:AddColor(soup.colors[id] or baseColor,1) end
			end
			local sharedColor=not soup.colors and editable:AddColor(baseColor,1) or nil
			for n,ti in ipairs(cluster.triangles) do
				local t=triangles[ti]
				local face=editable:AddTriangle(vertexIds[t[1]],vertexIds[t[2]],vertexIds[t[3]])
				editable:SetFaceUVs(face,{uvIds[t[1]],uvIds[t[2]],uvIds[t[3]]})
				editable:SetFaceNormals(face,{normalIds[t[1]],normalIds[t[2]],normalIds[t[3]]})
				if sharedColor then
					editable:SetFaceColors(face,{sharedColor,sharedColor,sharedColor})
				else
					editable:SetFaceColors(face,{colorIds[t[1]],colorIds[t[2]],colorIds[t[3]]})
				end
				if n%Limits.YIELD_EVERY==0 then yield() end
			end
			local content=bake(editable,"Conversao da malha "..ci.."/"..#plan,check)
			editable:Destroy()
			editable=nil
			local part=AssetService:CreateMeshPartAsync(content,{CollisionFidelity=collision,RenderFidelity=Enum.RenderFidelity.Precise})
			check()
			assert(part,"CreateMeshPartAsync nao retornou a submalha "..ci..".")
			part.Name=#plan==1 and tostring(soup.name or "Mesh") or tostring(soup.name or "Mesh")..string.format("_%03d",ci)
			part.Anchored=true
			part.CanCollide=options.canCollide~=false
			part.CanQuery=true
			part.CanTouch=true
			part.Color=WHITE
			part.Material=Enum.Material.SmoothPlastic
			part.DoubleSided=options.doubleSided==true
			part.Size=safeSize(part.MeshSize)
			part.CFrame=CFrame.new(center)
			if soup.textureContent then part.TextureContent=soup.textureContent end
			part:SetAttribute("ImportMCP_Triangles",#cluster.triangles)
			part:SetAttribute("ImportMCP_Vertices",#cluster.vertices)
			parts[#parts+1]=part
		end
	end,debug.traceback)
	if editable then editable:Destroy() end
	if not ok then
		for _,part in ipairs(parts) do part:Destroy() end
		error("Construcao da malha cancelada sem inserir geometria parcial. "..tostring(err),0)
	end
	return parts
end

return table.freeze(Mesh)
