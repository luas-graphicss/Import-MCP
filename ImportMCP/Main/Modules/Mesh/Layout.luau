local Limits=require(script.Parent.Parent.Runtime.Limits)

 
 
 
 
 
 
local Layout={}

Layout.SPLITS={auto=true,node=true,mesh=true,material=true,primitive=true,single=true,custom=true}

local ALIASES={
	nodes="node",object="node",objects="node",
	meshes="mesh",
	materials="material",legacy="material",
	primitives="primitive",prim="primitive",
	one="single",merge="single",merged="single",all="single",
	groups="custom",
}

local function lowerName(value)
	return string.lower(tostring(value or ""))
end

 
function Layout.options(options,name)
	options=options or {}
	local layout=type(options.layout)=="table" and table.clone(options.layout) or {}
	for _,key in ipairs({"split","groups","rename","rest","expect","strict","chunking"}) do
		if layout[key]==nil and options[key]~=nil then layout[key]=options[key] end
	end
	local split=lowerName(layout.split or "auto")
	split=ALIASES[split] or split
	if type(layout.groups)=="table" and #layout.groups>0 then split="custom" end
	assert(Layout.SPLITS[split],"split invalido: use auto, node, mesh, material, primitive, single ou informe groups.")
	if split=="custom" then assert(type(layout.groups)=="table" and #layout.groups>0,"split=custom exige a lista groups.") end
	layout.split=split
	layout.name=tostring(name or layout.name or "Modelo")
	if type(layout.expect)=="table" and layout.strict==nil and layout.expect.strict~=nil then layout.strict=layout.expect.strict end
	return layout
end

local function globToPattern(glob)
	local pattern=glob:gsub("[%^%$%(%)%%%.%[%]%+%-]","%%%0")
	pattern=pattern:gsub("%*",".*"):gsub("%?",".")
	return "^"..pattern.."$"
end

 
function Layout.matches(pattern,text)
	if text==nil or pattern==nil then return false end
	text=tostring(text)
	pattern=tostring(pattern)
	if pattern=="" then return false end
	if pattern:sub(1,1)=="~" then
		local ok,found=pcall(string.find,text,pattern:sub(2))
		return ok and found~=nil
	end
	return string.find(string.lower(text),globToPattern(string.lower(pattern)))~=nil
end

local function listHas(list,value)
	if type(list)~="table" then return false end
	for _,entry in ipairs(list) do
		if entry==value then return true end
	end
	return false
end

local function itemMatches(spec,item)
	if type(spec)=="string" then return Layout.matches(spec,item.nodeName) or Layout.matches(spec,item.meshName) end
	if type(spec)~="table" then return false end
	if listHas(spec.nodes,item.node) or listHas(spec.meshes,item.mesh) or listHas(spec.materials,item.material) then return true end
	if type(spec.materials)=="table" then
		for _,entry in ipairs(spec.materials) do
			if type(entry)=="string" and Layout.matches(entry,item.materialName) then return true end
		end
	end
	local patterns=spec.match or spec.patterns or spec.names or spec.nodeNames
	if type(patterns)=="string" then patterns={patterns} end
	if type(patterns)=="table" then
		for _,pattern in ipairs(patterns) do
			if Layout.matches(pattern,item.nodeName) or Layout.matches(pattern,item.meshName) then return true end
		end
	end
	local materials=spec.materialNames
	if type(materials)=="string" then materials={materials} end
	if type(materials)=="table" then
		for _,pattern in ipairs(materials) do
			if Layout.matches(pattern,item.materialName) then return true end
		end
	end
	return false
end

local function itemLabel(item)
	return tostring(item.nodeName or item.meshName or ("Malha "..tostring((item.mesh or 0)+1)))
end

local function materialKey(item)
	return string.format("%s|%s|%.3f|%s",tostring(item.texture or "-"),tostring(item.colorKey or "-"),item.alpha or 1,tostring(item.doubleSided==true))
end

local function applyRename(name,rename)
	if type(rename)~="table" then return name,false end
	if rename[name]~=nil then return tostring(rename[name]),true end
	local lowered=string.lower(name)
	for key,value in pairs(rename) do
		if type(key)=="string" and string.lower(key)==lowered then return tostring(value),true end
	end
	for key,value in pairs(rename) do
		if type(key)=="string" and (key:find("[%*%?]") or key:sub(1,1)=="~") and Layout.matches(key,name) then return tostring(value),true end
	end
	return name,false
end

local function cleanName(name,fallback)
	name=tostring(name or ""):gsub("[%c]",""):gsub("^%s+",""):gsub("%s+$","")
	if name=="" then name=fallback or "Malha" end
	return name:sub(1,100)
end

 
function Layout.chunks(triangles,vertices)
	return math.max(1,math.ceil((triangles or 0)/Limits.CHUNK_TRIANGLES),math.ceil((vertices or 0)/Limits.CHUNK_VERTICES))
end

function Layout.plan(items,layout)
	layout=layout or Layout.options(nil)
	assert(type(items)=="table","Itens de layout invalidos.")
	local plan={split=layout.split,groups={},notes={},dropped={},unmatchedGroups={}}
	local nodes={}
	local distinct=0
	for _,item in ipairs(items) do
		local key=item.node or ("m"..tostring(item.mesh))
		if not nodes[key] then nodes[key]=true distinct+=1 end
	end
	local split=layout.split
	if split=="auto" then
		split=distinct<=Limits.AUTO_NODE_LIMIT and "node" or "material"
		plan.autoReason=string.format("%d no(s) com malha: split automatico = %s (limite %d).",distinct,split,Limits.AUTO_NODE_LIMIT)
	end
	plan.split=split
	local buckets,order={},{}
	local function bucket(key,name,source)
		local group=buckets[key]
		if not group then
			group={key=key,name=cleanName(name,"Malha"),items={},source=source}
			buckets[key]=group
			order[#order+1]=group
		end
		return group
	end
	local function byNode(item)
		return bucket("node:"..tostring(item.node or ("m"..tostring(item.mesh))),itemLabel(item),"node")
	end
	if split=="custom" then
		local assigned={}
		for gi,spec in ipairs(layout.groups) do
			local name=type(spec)=="table" and (spec.name or spec.as) or nil
			if name==nil and type(spec)=="string" then name=spec end
			name=cleanName(name,"Grupo"..gi)
			local group=bucket("custom:"..gi,name,"custom")
			group.spec=spec
			for _,item in ipairs(items) do
				if not assigned[item.index] and itemMatches(spec,item) then
					assigned[item.index]=true
					group.items[#group.items+1]=item
				end
			end
		end
		local kept={}
		for _,group in ipairs(order) do
			if #group.items>0 then
				kept[#kept+1]=group
			else
				plan.unmatchedGroups[#plan.unmatchedGroups+1]=group.name
				plan.notes[#plan.notes+1]="Grupo '"..group.name.."' nao casou com nenhuma malha do arquivo."
				buckets[group.key]=nil
			end
		end
		order=kept
		local rest=layout.rest
		local restMode=type(rest)=="table" and lowerName(rest.mode or rest.split or "node") or lowerName(rest or "node")
		restMode=ALIASES[restMode] or restMode
		local restName=type(rest)=="table" and rest.name or "Outros"
		for _,item in ipairs(items) do
			if not assigned[item.index] then
				if restMode=="drop" or restMode=="ignore" or restMode=="skip" then
					plan.dropped[#plan.dropped+1]=itemLabel(item)
				elseif restMode=="error" or restMode=="fail" then
					local names={}
					for _,other in ipairs(items) do
						if not assigned[other.index] then names[#names+1]=itemLabel(other) end
					end
					error("Malhas fora dos grupos informados: "..table.concat(names,", ")..". Ajuste groups ou use rest='node'|'merge'|'drop'.",0)
				elseif restMode=="single" or restMode=="merge" then
					local group=bucket("rest",restName,"rest")
					group.items[#group.items+1]=item
				elseif restMode=="material" then
					local group=bucket("rest:"..materialKey(item),itemLabel(item),"rest")
					group.items[#group.items+1]=item
				else
					local group=byNode(item)
					group.items[#group.items+1]=item
				end
			end
		end
		if #plan.dropped>0 then plan.notes[#plan.notes+1]=#plan.dropped.." malha(s) descartada(s) por rest='drop'." end
	else
		for _,item in ipairs(items) do
			local group
			if split=="node" then
				group=byNode(item)
			elseif split=="mesh" then
				group=bucket("mesh:"..tostring(item.mesh),item.meshName or itemLabel(item),"mesh")
			elseif split=="primitive" then
				group=bucket("prim:"..tostring(item.index),itemLabel(item),"primitive")
			elseif split=="single" then
				group=bucket("all",layout.name,"single")
			else
				group=bucket("mat:"..materialKey(item),itemLabel(item),"material")
			end
			group.items[#group.items+1]=item
		end
		if split=="material" and #order==1 then order[1].name=cleanName(layout.name,order[1].name) end
	end
	 
	local expanded={}
	for _,group in ipairs(order) do
		local partitions,partitionOrder={},{}
		for _,item in ipairs(group.items) do
			local key=tostring(item.texture or "none")
			local partition=partitions[key]
			if not partition then
				partition={texture=item.texture,items={},triangles=0}
				partitions[key]=partition
				partitionOrder[#partitionOrder+1]=partition
			end
			partition.items[#partition.items+1]=item
			partition.triangles+=item.triangles or 0
		end
		if #partitionOrder>1 then
			table.sort(partitionOrder,function(a,b) return a.triangles>b.triangles end)
			plan.notes[#plan.notes+1]=string.format("'%s' usa %d texturas; virou %d MeshParts (um MeshPart aceita uma textura).",group.name,#partitionOrder,#partitionOrder)
		end
		for pi,partition in ipairs(partitionOrder) do
			expanded[#expanded+1]={name=pi==1 and group.name or string.format("%s_%d",group.name,pi),items=partition.items,texture=partition.texture,source=group.source,spec=group.spec,parentName=group.name}
		end
	end
	 
	local used={}
	for _,group in ipairs(expanded) do
		local color,alpha,sameColor=nil,nil,true
		local doubleSided,skinned,vertexColors=false,false,false
		local triangles,vertices=0,0
		local sources,seen={},{}
		for _,item in ipairs(group.items) do
			if color==nil then
				color,alpha=item.colorKey,item.alpha or 1
			elseif item.colorKey~=color or math.abs((item.alpha or 1)-alpha)>0.002 then
				sameColor=false
			end
			if (item.alpha or 1)>(alpha or 1) then alpha=item.alpha end
			doubleSided=doubleSided or item.doubleSided==true
			skinned=skinned or item.skinned==true
			vertexColors=vertexColors or item.hasVertexColors==true
			triangles+=item.triangles or 0
			vertices+=item.vertices or 0
			local label=itemLabel(item)
			if not seen[label] then
				seen[label]=true
				sources[#sources+1]=label
			end
		end
		group.colors=(not sameColor) or vertexColors
		group.colorKey=sameColor and color or nil
		group.transparency=1-(alpha or 1)
		group.doubleSided=doubleSided
		group.skinned=skinned
		group.triangles=triangles
		group.vertices=vertices
		group.sources=sources
		group.chunks=Layout.chunks(triangles,vertices)
		local renamed,changed=applyRename(group.name,layout.rename)
		if changed then group.name=cleanName(renamed,group.name) end
		local base=group.name
		if used[base] then
			local n=2
			while used[base.."_"..n] do n+=1 end
			group.name=base.."_"..n
		end
		used[group.name]=true
		if not sameColor then plan.notes[#plan.notes+1]=string.format("'%s' mistura materiais sem textura; as cores foram gravadas por vertice.",group.name) end
	end
	plan.groups=expanded
	return plan
end

 
function Layout.check(plan,boneNames,expect)
	local problems={}
	if type(expect)~="table" then return problems end
	local names={}
	local lookup={}
	for _,group in ipairs(plan.groups) do
		names[#names+1]=group.name
		lookup[string.lower(group.name)]=true
	end
	local expectedNames=expect.names or expect.meshes
	local count=expect.parts or expect.count
	if type(count)=="table" then
		expectedNames=expectedNames or count
		count=#count
	end
	if type(expectedNames)=="string" then expectedNames={expectedNames} end
	if type(expectedNames)=="table" and count==nil then count=#expectedNames end
	if type(count)=="number" and #plan.groups~=count then
		problems[#problems+1]=string.format("esperava %d MeshPart(s), o layout produz %d: %s",count,#plan.groups,table.concat(names,", "))
	end
	if type(expect.maxParts)=="number" and #plan.groups>expect.maxParts then
		problems[#problems+1]=string.format("layout produz %d MeshParts, acima de maxParts=%d",#plan.groups,expect.maxParts)
	end
	if type(expectedNames)=="table" then
		local missing,wanted={},{}
		for _,name in ipairs(expectedNames) do
			wanted[string.lower(tostring(name))]=true
			if not lookup[string.lower(tostring(name))] then missing[#missing+1]=tostring(name) end
		end
		if #missing>0 then problems[#problems+1]="MeshParts esperados ausentes: "..table.concat(missing,", ") end
		if expect.exact~=false then
			local extra={}
			for _,name in ipairs(names) do
				if not wanted[string.lower(name)] then extra[#extra+1]=name end
			end
			if #extra>0 then problems[#problems+1]="MeshParts fora do esperado: "..table.concat(extra,", ") end
		end
	end
	local bones=expect.bones or expect.joints
	if bones~=nil then
		boneNames=boneNames or {}
		local have={}
		for _,name in ipairs(boneNames) do have[string.lower(tostring(name))]=true end
		if type(bones)=="number" then
			if #boneNames~=bones then problems[#problems+1]=string.format("esperava %d osso(s), o rig tem %d",bones,#boneNames) end
		elseif type(bones)=="table" then
			local missing={}
			for _,name in ipairs(bones) do
				if not have[string.lower(tostring(name))] then missing[#missing+1]=tostring(name) end
			end
			if #missing>0 then problems[#problems+1]="ossos esperados ausentes: "..table.concat(missing,", ") end
		end
	end
	if expect.skinned==true and #(boneNames or {})==0 then problems[#problems+1]="esperava um rig com skinning, mas o arquivo nao tem skins/pesos." end
	if type(expect.chunks)=="number" or expect.noChunks==true then
		for _,group in ipairs(plan.groups) do
			if group.chunks>1 then problems[#problems+1]=string.format("'%s' tem %d triangulos e sera dividido em %d submalhas (limite %d por MeshPart)",group.name,group.triangles,group.chunks,Limits.CHUNK_TRIANGLES) end
		end
	end
	return problems
end

 
function Layout.summary(plan,boneNames)
	local parts={}
	for _,group in ipairs(plan.groups) do
		parts[#parts+1]={name=group.name,triangles=group.triangles,vertices=group.vertices,chunks=group.chunks,texture=group.texture~=nil,sources=group.sources,skinned=group.skinned==true,vertexColors=group.colors==true,transparency=group.transparency,doubleSided=group.doubleSided}
	end
	return {split=plan.split,parts=parts,count=#parts,notes=plan.notes,dropped=plan.dropped,unmatchedGroups=plan.unmatchedGroups,autoReason=plan.autoReason,bones=boneNames}
end

return table.freeze(Layout)
