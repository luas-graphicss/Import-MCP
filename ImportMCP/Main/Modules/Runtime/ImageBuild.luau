local ImageDecode=require(script.Parent.ImageDecode)
local Materialize=require(script.Parent.Materialize)
local AssetService=game:GetService("AssetService")

local ImageBuild={}

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

function ImageBuild.editable(image,check)
	assert(type(image)=="table" and typeof(image.pixels)=="buffer","Imagem decodificada invalida.")
	local editable=AssetService:CreateEditableImage({Size=Vector2.new(image.width,image.height)})
	assert(editable,"EditableImage indisponivel; confira memoria e permissoes de Image APIs.")
	if check then check() end
	editable:WritePixelsBuffer(Vector2.zero,Vector2.new(image.width,image.height),image.pixels)
	return editable
end

 
 
 
function ImageBuild.content(image,options)
	options=options or {}
	local editable=ImageBuild.editable(image,options.check)
	local info={width=image.width,height=image.height,format=image.format,hasAlpha=image.hasAlpha,sourceWidth=image.sourceWidth,sourceHeight=image.sourceHeight,resized=image.resized==true}
	if options.mode=="asset" then
		if options.stage then options.stage("enviando") end
		local ok,result=pcall(Materialize.upload,editable,Enum.AssetType.Image,options.name or "Imagem",{check=options.check})
		if ok then
			editable:Destroy()
			info.mode="asset"
			info.assetId=result
			info.baked=true
			return Content.fromAssetId(result),info
		end
		if options.fallback==false or not Materialize.isFallbackError(result) then
			editable:Destroy()
			error(Materialize.errorText(result),0)
		end
		info.fallback=Materialize.errorText(result)
	end
	local content,baked=bake(editable,"Conversao da imagem",options.check)
	if baked then
		editable:Destroy()
	else
		retained[#retained+1]=editable
	end
	info.mode="session"
	info.baked=baked
	return content,info
end

function ImageBuild.fromBytes(bytes,options)
	options=options or {}
	local image=ImageDecode.decode(bytes,{yield=options.yield,maxSize=options.maxSize,width=options.width,height=options.height})
	if options.check then options.check() end
	return ImageBuild.content(image,options)
end

function ImageBuild.property(instance)
	if instance:IsA("MeshPart") or instance:IsA("Decal") or instance:IsA("Texture") then return "TextureContent" end
	if instance:IsA("ImageLabel") or instance:IsA("ImageButton") then return "ImageContent" end
	if instance:IsA("SurfaceAppearance") then return "ColorMapContent" end
	return nil
end

function ImageBuild.apply(instance,content,property)
	property=property or ImageBuild.property(instance)
	assert(property,"A classe "..instance.ClassName.." nao aceita conteudo de imagem.")
	instance[property]=content
	return property
end

return table.freeze(ImageBuild)
