local Limits=require(script.Parent.Limits)
local Store=require(script.Parent.Store)
local Codec=require(script.Parent.Codec)
local MeshBuild=require(script.Parent.MeshBuild)
local ImageBuild=require(script.Parent.ImageBuild)
local Yield=require(script.Parent.Yield)
local LiveToken=require(script.Parent.LiveToken)

local Loader={}

local loading=setmetatable({},{__mode="k"})

function Loader.package(root)
	local package=root:FindFirstChild(Limits.PACKAGE)
	if package and package:IsA("Folder") then return package end
	return nil
end

function Loader.kind(root)
	if typeof(root)~="Instance" then return nil end
	local kind=root:GetAttribute("ImportMCP_Kind")
	if (kind=="Mesh" or kind=="Image") and Loader.package(root) then return kind end
	return nil
end

local function hasContent(content)
	return typeof(content)=="Content" and content.SourceType~=Enum.ContentSourceType.None
end

 
 
function Loader.materialized(root)
	local kind=Loader.kind(root)
	if not kind or not LiveToken.isLive(root) then return false end
	local ok,present=pcall(function()
		if kind=="Mesh" then
			local targets=MeshBuild.parts(root)
			if #targets==0 then return false end
			for _,target in ipairs(targets) do
				if not hasContent(target.MeshContent) then return false end
			end
			return true
		end
		local property=root:GetAttribute("ImportMCP_Property") or ImageBuild.property(root)
		return property~=nil and hasContent(root[property])
	end)
	return ok and present==true
end

local function restoreMesh(root,package,options,check,yield)
	local data=Store.read(package,Codec.MAGIC,yield)
	local snapshot=Codec.decode(data,yield)
	check()
	local targets=MeshBuild.parts(root)
	assert(#targets>0,"Geometria original ausente em "..root:GetFullName()..".")
	local collisions={}
	for index,target in ipairs(targets) do
		collisions[index]=target.CollisionFidelity.Name
	end
	local fresh=MeshBuild.build(snapshot,{collisionByChunk=collisions,check=check,yield=yield,name=root.Name,skeleton=false})
	local ok,err=pcall(function()
		local replacements=MeshBuild.parts(fresh)
		assert(#replacements==#targets,"Contagem de submalhas diferente ("..#replacements.." vs "..#targets.."); nao altere os chunks gerados.")
		check()
		local function apply()
			for index,target in ipairs(targets) do
				local replacement=replacements[index]
				local cframe,size,pivot=target.CFrame,target.Size,target.PivotOffset
				target:ApplyMesh(replacement)
				target.TextureContent=replacement.TextureContent
				target.CFrame=cframe
				target.Size=size
				target.PivotOffset=pivot
			end
			root:SetAttribute("ImportMCP_Status","Ready")
			root:SetAttribute("ImportMCP_LastError",nil)
			LiveToken.stamp(root)
		end
		if options.commit then options.commit(apply) else apply() end
	end)
	fresh:Destroy()
	if not ok then error(err,0) end
	return #targets
end

local function restoreImage(root,package,options,check,yield)
	local data=Store.read(package,"IMG1",yield)
	local property=root:GetAttribute("ImportMCP_Property") or ImageBuild.property(root)
	assert(property,"Propriedade de imagem desconhecida para "..root.ClassName..".")
	local content=ImageBuild.fromBytes(data,{yield=yield,check=check,maxSize=root:GetAttribute("ImportMCP_MaxSize")})
	check()
	local function apply()
		root[property]=content
		root:SetAttribute("ImportMCP_Status","Ready")
		root:SetAttribute("ImportMCP_LastError",nil)
		LiveToken.stamp(root)
	end
	if options.commit then options.commit(apply) else apply() end
	return 1
end

function Loader.restore(root,options)
	options=options or {}
	local kind=Loader.kind(root)
	assert(kind,"Instancia sem pacote ImportMCP: "..tostring(root and root:GetFullName()))
	 
	 
	 
	if LiveToken.hosted() and not options.force and Loader.materialized(root) then
		return 0
	end
	assert(not loading[root],"Esta instancia ja esta sendo reconstruida.")
	loading[root]=true
	local function check()
		assert(root.Parent~=nil,"Instancia removida durante a reconstrucao.")
		assert(not options.shouldContinue or options.shouldContinue(),"Reconstrucao cancelada.")
	end
	local yield=Yield.ticker(check)
	local package=Loader.package(root)
	local ok,result=xpcall(function()
		check()
		root:SetAttribute("ImportMCP_Status","Rebuilding")
		if kind=="Mesh" then return restoreMesh(root,package,options,check,yield) end
		return restoreImage(root,package,options,check,yield)
	end,debug.traceback)
	loading[root]=nil
	if not ok then
		pcall(function()
			root:SetAttribute("ImportMCP_Status","Error")
			root:SetAttribute("ImportMCP_LastError",tostring(result):match("^[^\n]+"):sub(1,900))
		end)
		error(result,0)
	end
	return result
end

return table.freeze(Loader)
