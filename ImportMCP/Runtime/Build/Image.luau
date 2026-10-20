local Limits=require(script.Parent.Parent.Limits)
local Codec=require(script.Parent.Parent.Codecs.Image)
local AssetService=game:GetService("AssetService")

local Image={}

function Image.decode(bytes,options)
	options=options or {}
	local limit=math.floor(tonumber(options.maxSize) or Limits.MAX_TEXTURE)
	limit=math.clamp(limit,16,Limits.MAX_TEXTURE)
	return Codec.decode(bytes,{maxSize=limit,yield=options.yield})
end

function Image.content(image,check)
	assert(type(image)=="table" and typeof(image.pixels)=="buffer","Imagem decodificada invalida.")
	assert(image.width>=1 and image.height>=1 and image.width<=Limits.MAX_TEXTURE and image.height<=Limits.MAX_TEXTURE,"Dimensao de imagem fora do limite.")
	assert(buffer.len(image.pixels)==image.width*image.height*4,"Buffer de pixels inconsistente.")
	local editable=AssetService:CreateEditableImage({Size=Vector2.new(image.width,image.height)})
	assert(editable,"EditableImage indisponivel; confira memoria e permissao de Mesh/Image APIs.")
	local ok,result,content=pcall(function()
		editable:WritePixelsBuffer(Vector2.zero,Vector2.new(image.width,image.height),image.pixels)
		return AssetService:CreateDataModelContentAsync(Content.fromObject(editable))
	end)
	editable:Destroy()
	if not ok then error("Falha ao converter imagem em Content: "..tostring(result),0) end
	if check then check() end
	assert(typeof(result)=="EnumItem" and result.Name=="Success" and typeof(content)=="Content","Conversao da imagem falhou: "..tostring(result))
	return content
end

function Image.fromBytes(bytes,options)
	options=options or {}
	local image=Image.decode(bytes,options)
	local content=Image.content(image,options.check)
	return content,image
end

function Image.describe(image)
	return Codec.describe(image)
end

return table.freeze(Image)
