local Runtime=script.Parent.Parent.Runtime
local Model=require(Runtime.Build.Model)

local Insert3D={}

local function vector3(value,fallback)
	if typeof(value)=="Vector3" then return value end
	if type(value)=="table" then
		if #value==3 then return Vector3.new(value[1],value[2],value[3]) end
		if value.x or value.y or value.z then return Vector3.new(value.x or 0,value.y or 0,value.z or 0) end
	end
	return fallback
end

local function cframeOf(options)
	local position=vector3(options.position,Vector3.zero)
	local rotation=vector3(options.rotation,nil)
	if rotation then
		return CFrame.new(position)*CFrame.fromOrientation(math.rad(rotation.X),math.rad(rotation.Y),math.rad(rotation.Z))
	end
	return CFrame.new(position)
end

local function applyProps(instance,props,warnings)
	if type(props)~="table" then return end
	for key,value in pairs(props) do
		local ok,err=pcall(function() instance[key]=value end)
		if not ok then warnings[#warnings+1]="Propriedade '"..tostring(key).."' ignorada: "..tostring(err):match("^[^\n]+") end
	end
end

function Insert3D.import(bytes,externals,parent,options)
	local warnings={}
	local wantsSingle=options.className=="MeshPart"
	local parts,info=Model.build(bytes,{
		externals=externals,
		scale=options.scale,
		maxSize=options.maxSize,
		merge=wantsSingle,
		collision=options.collision,
		center=options.center,
		ground=options.ground,
		doubleSided=options.doubleSided,
		canCollide=options.canCollide,
		name=options.name,
		yield=options.yield,
		check=options.check,
	})
	for _,note in ipairs(info.notes or {}) do warnings[#warnings+1]=note end
	if info.skipped>0 then warnings[#warnings+1]=info.skipped.." primitiva(s) ignorada(s) no glTF." end
	local root
	if wantsSingle and #parts==1 then
		root=parts[1]
		root.Name=options.name
		root.CFrame=cframeOf(options)*root.CFrame
	else
		if wantsSingle then warnings[#warnings+1]="Malha grande demais para um unico MeshPart; inserida como Model com "..#parts.." partes." end
		root=Instance.new("Model")
		root.Name=options.name
		for _,part in ipairs(parts) do part.Parent=root end
		root.WorldPivot=CFrame.new()
		root:PivotTo(cframeOf(options))
	end
	applyProps(root,options.props,warnings)
	root.Parent=parent
	return {
		instance=root,
		parts=#parts,
		meshes=info.meshes,
		triangles=info.triangles,
		textures=info.textures,
		merged=wantsSingle,
		warnings=warnings,
	}
end

return table.freeze(Insert3D)
