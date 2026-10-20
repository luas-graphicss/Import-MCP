local Accessors=require(script.Parent.Accessors)
local Nodes=require(script.Parent.Nodes)
local Limits=require(script.Parent.Parent.Runtime.Limits)

 
 
 
local Rig={}

local CONTROLLERS={animationcontroller="AnimationController",animator="AnimationController",controller="AnimationController",humanoid="Humanoid",none="none",["false"]="none",off="none"}

local function cleanName(name,fallback)
	name=tostring(name or ""):gsub("[%c]",""):gsub("^%s+",""):gsub("%s+$","")
	if name=="" then name=fallback end
	return name:sub(1,100)
end

function Rig.collect(doc,options)
	options=options or {}
	local json=doc.json
	local skins=json.skins
	if type(skins)~="table" or #skins==0 then return nil end
	local nodes=json.nodes or {}
	local parents=Nodes.parents(json)
	local jointSet={}
	local bindByNode={}
	local skinInfo={}
	for si,skin in ipairs(skins) do
		if type(skin)=="table" and type(skin.joints)=="table" then
			local ibm
			if skin.inverseBindMatrices~=nil then
				local ok,values,width,count=pcall(Accessors.read,doc,skin.inverseBindMatrices,options.yield)
				if ok and width==16 then ibm={values=values,count=count} end
			end
			local info={joints={},name=type(skin.name)=="string" and skin.name or nil}
			for j,nodeIndex in ipairs(skin.joints) do
				if type(nodeIndex)=="number" and nodes[nodeIndex+1] then
					jointSet[nodeIndex]=true
					info.joints[j]=nodeIndex
					if bindByNode[nodeIndex]==nil and ibm and j<=ibm.count then
						local slot=(j-1)*16
						local columns=table.create(16)
						for k=1,16 do columns[k]=ibm.values[slot+k] end
						local okMatrix,matrix=pcall(Nodes.fromArray,columns)
						if okMatrix then
							local inverse=Nodes.inverse(matrix)
							if inverse then bindByNode[nodeIndex]=inverse end
						end
					end
				end
			end
			skinInfo[si-1]=info
		end
	end
	local parentJoint={}
	local sorted={}
	for nodeIndex in pairs(jointSet) do
		sorted[#sorted+1]=nodeIndex
		local current=parents[nodeIndex]
		local depth=0
		while current~=nil and not jointSet[current] do
			current=parents[current]
			depth+=1
			if depth>512 then current=nil end
		end
		parentJoint[nodeIndex]=current
	end
	if #sorted==0 then return nil end
	table.sort(sorted)
	local children,roots={},{}
	for _,nodeIndex in ipairs(sorted) do
		local parent=parentJoint[nodeIndex]
		if parent==nil then
			roots[#roots+1]=nodeIndex
		else
			children[parent]=children[parent] or {}
			table.insert(children[parent],nodeIndex)
		end
	end
	local bones,byNode={},{}
	local function visit(nodeIndex,parentBone,depth)
		assert(depth<=512,"Hierarquia de ossos profunda demais.")
		local node=nodes[nodeIndex+1]
		local bind=bindByNode[nodeIndex] or Nodes.global(json,nodeIndex,parents)
		bones[#bones+1]={node=nodeIndex,raw=type(node.name)=="string" and node.name or ("Bone_"..nodeIndex),parent=parentBone,bind=bind,fromIbm=bindByNode[nodeIndex]~=nil}
		byNode[nodeIndex]=#bones
		local self=#bones
		for _,child in ipairs(children[nodeIndex] or {}) do visit(child,self,depth+1) end
	end
	for _,root in ipairs(roots) do visit(root,nil,1) end
	assert(#bones<=Limits.MAX_BONES,"O rig tem "..#bones.." ossos; o limite e "..Limits.MAX_BONES..".")
	for _,info in pairs(skinInfo) do
		local mapped={}
		for j,nodeIndex in pairs(info.joints) do mapped[j]=byNode[nodeIndex] end
		info.joints=mapped
		local root=mapped[1] or 1
		while root and bones[root] and bones[root].parent do root=bones[root].parent end
		info.root=root or 1
	end
	return {bones=bones,byNode=byNode,joints=jointSet,skins=skinInfo,count=#bones,roots=#roots}
end

local function commonPrefix(bones)
	local prefix
	for _,bone in ipairs(bones) do
		local candidate=bone.raw:match("^([^:]+:)") or bone.raw:match("^([%a]+_)")
		if not candidate then return nil end
		if prefix==nil then prefix=candidate elseif prefix~=candidate then return nil end
	end
	return prefix
end

 
 
 
function Rig.apply(rig,options)
	options=type(options)=="table" and options or {}
	local strip=options.stripPrefix
	if strip==true or strip=="auto" then strip=commonPrefix(rig.bones) end
	local rename=options.rename or options.map or options.bones
	if type(rename)~="table" then rename=nil end
	local lowered={}
	if rename then
		for key,value in pairs(rename) do
			if type(key)=="string" then lowered[string.lower(key)]=value end
		end
	end
	local used={}
	for _,bone in ipairs(rig.bones) do
		local name=bone.raw
		if type(strip)=="string" and #strip>0 and name:sub(1,#strip)==strip then name=name:sub(#strip+1) end
		if rename then
			local mapped=rename[bone.raw]
			if mapped==nil then mapped=rename[name] end
			if mapped==nil then mapped=lowered[string.lower(bone.raw)] end
			if mapped==nil then mapped=lowered[string.lower(name)] end
			if mapped~=nil then name=tostring(mapped) end
		end
		name=cleanName(name,"Bone_"..bone.node)
		if used[name] then
			local n=2
			while used[name.."_"..n] do n+=1 end
			name=name.."_"..n
		end
		used[name]=true
		bone.name=name
	end
	rig.rootName=cleanName(options.rootName or options.root,"RootPart")
	local controller=CONTROLLERS[string.lower(tostring(options.controller or options.animator or "AnimationController"))]
	assert(controller,"rig.controller invalido: use AnimationController, Humanoid ou none.")
	rig.controller=controller
	rig.rootAt=options.rootAt=="bone" and "bone" or "origin"
	rig.rootSize=options.rootSize
	rig.stripped=strip
	return rig
end

function Rig.names(rig)
	local out={}
	for index,bone in ipairs(rig.bones) do out[index]=bone.name or bone.raw end
	return out
end

 
function Rig.cframes(rig,scale,offset)
	scale=scale or 1
	offset=offset or Vector3.zero
	local out={}
	for index,bone in ipairs(rig.bones) do
		local cframe=Nodes.toCFrame(bone.bind)
		cframe=CFrame.new(cframe.Position*scale+offset)*cframe.Rotation
		out[index]=cframe
	end
	return out
end

 
function Rig.describe(rig,limit)
	limit=limit or 256
	local list={}
	for index,bone in ipairs(rig.bones) do
		if index>limit then break end
		list[index]={name=bone.name or bone.raw,source=bone.raw,parent=bone.parent and (rig.bones[bone.parent].name or rig.bones[bone.parent].raw) or nil,bindFromIbm=bone.fromIbm}
	end
	local skins=0
	for _ in pairs(rig.skins) do skins+=1 end
	return {count=rig.count,roots=rig.roots,skins=skins,bones=list,rootName=rig.rootName,controller=rig.controller,strippedPrefix=rig.stripped}
end

return table.freeze(Rig)
