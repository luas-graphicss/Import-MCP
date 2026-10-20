local Gltf=require(script.Parent.Parent.Gltf.Gltf)
local Image=require(script.Parent.Image)
local Mesh=require(script.Parent.Mesh)
local HttpService=game:GetService("HttpService")

local Model={}

local function decodeJson(text)
	return HttpService:JSONDecode(text)
end

local function normalizeExternals(externals)
	local out={}
	if type(externals)~="table" then return out end
	for name,value in pairs(externals) do
		local key=string.lower(tostring(name))
		if type(value)=="string" then
			out[key]=buffer.fromstring(value)
		elseif typeof(value)=="buffer" then
			out[key]=value
		end
		local root=string.match(key,"^(.-)%.[%w]+$")
		if root and out[root]==nil then out[root]=out[key] end
	end
	return out
end

function Model.decode(bytes,options)
	options=options or {}
	local contents=typeof(bytes)=="buffer" and buffer.tostring(bytes) or bytes
	assert(type(contents)=="string","Conteudo glTF invalido.")
	local doc=Gltf.parse(contents,{decodeJson=decodeJson})
	Gltf.resolveBuffers(doc,{externals=normalizeExternals(options.externals),yield=options.yield})
	local soups,skipped,report=Gltf.build(doc,{scale=options.scale or 1,yield=options.yield})
	return doc,soups,skipped,report
end

function Model.textures(doc,soups,options)
	options=options or {}
	local contents={}
	local notes={}
	local decoded=0
	for _,soup in ipairs(soups) do
		local index=soup.texture
		if index~=nil then
			local hit=contents[index]
			if hit==nil then
				local ok,result=pcall(function()
					local bytes=Gltf.imageBytes(doc,index,options.yield)
					assert(bytes,"Imagem "..tostring(index).." ausente no arquivo.")
					local content=Image.fromBytes(bytes,{maxSize=options.maxSize,yield=options.yield,check=options.check})
					return content
				end)
				if ok then
					hit=result
					decoded+=1
				else
					hit=false
					notes[#notes+1]="Textura "..tostring(index)..": "..(tostring(result):match("^[^\n]+") or tostring(result))
				end
				contents[index]=hit
			end
			if hit then soup.textureContent=hit end
		end
	end
	return decoded,notes
end

function Model.build(bytes,options)
	options=options or {}
	local yield=options.yield or function() end
	local check=options.check or function() end
	local doc,soups,skipped,report=Model.decode(bytes,{externals=options.externals,scale=options.scale,yield=yield})
	check()
	local textures,notes=Model.textures(doc,soups,{maxSize=options.maxSize,yield=yield,check=check})
	if options.merge then
		soups={Mesh.merge(soups,options.name,yield)}
	elseif options.name and #soups==1 then
		soups[1].name=options.name
	end
	Mesh.center(soups,{center=options.center~=false,ground=options.ground==true})
	local parts={}
	local ok,err=xpcall(function()
		for _,soup in ipairs(soups) do
			local built=Mesh.build(soup,{yield=yield,check=check,collision=options.collision,doubleSided=options.doubleSided,canCollide=options.canCollide})
			for _,part in ipairs(built) do parts[#parts+1]=part end
		end
	end,debug.traceback)
	if not ok then
		for _,part in ipairs(parts) do part:Destroy() end
		error(err,0)
	end
	for index,part in ipairs(parts) do part:SetAttribute("ImportMCP_Part",index) end
	return parts,{
		meshes=#soups,
		parts=#parts,
		triangles=report and report.triangles or 0,
		skipped=skipped or 0,
		textures=textures,
		notes=notes,
	}
end

return table.freeze(Model)
