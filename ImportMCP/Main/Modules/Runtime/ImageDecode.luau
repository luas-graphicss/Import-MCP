local Png=require(script.Parent.Png)
local Jpeg=require(script.Parent.Jpeg)
local Resample=require(script.Parent.Resample)
local Limits=require(script.Parent.Limits)

local ImageDecode={}

local ENGINES={png=Png,jpeg=Jpeg}
local FORMAT_CODES={png=1,jpeg=2}
local FORMAT_NAMES={[1]="png",[2]="jpeg"}

ImageDecode.FORMAT_CODES=FORMAT_CODES
ImageDecode.FORMAT_NAMES=FORMAT_NAMES

local function toBuffer(source)
	if type(source)=="string" then return buffer.fromstring(source) end
	return source
end

function ImageDecode.kind(source)
	source=toBuffer(source)
	if typeof(source)~="buffer" or buffer.len(source)<12 then return nil end
	if Png.matches(source) then return "png" end
	if Jpeg.matches(source) then return "jpeg" end
	return nil
end

function ImageDecode.matches(source)
	return ImageDecode.kind(source)~=nil
end

function ImageDecode.fromName(name)
	local lowered=string.lower(tostring(name or ""))
	if lowered:match("%.png$") then return "png" end
	if lowered:match("%.jpe?g$") or lowered:match("%.jpe$") then return "jpeg" end
	return nil
end

function ImageDecode.probe(source)
	source=toBuffer(source)
	local kind=ImageDecode.kind(source)
	if kind=="png" then
		local info=Png.probe(source)
		if info then return {format="png",width=info.width,height=info.height} end
	end
	return kind and {format=kind} or nil
end

function ImageDecode.decode(source,options)
	options=options or {}
	source=toBuffer(source)
	assert(typeof(source)=="buffer","Conteudo de imagem invalido.")
	local total=buffer.len(source)
	assert(total>=16,"Arquivo de imagem vazio ou truncado.")
	assert(total<=Limits.MAX_IMAGE_BYTES,"Imagem acima de "..(Limits.MAX_IMAGE_BYTES//1048576).." MiB.")
	local kind=ImageDecode.kind(source)
	assert(kind,"Formato de imagem nao reconhecido; envie PNG ou JPEG.")
	local limit=math.floor(tonumber(options.maxSize) or Limits.MAX_TEXTURE)
	limit=math.clamp(limit,16,Limits.MAX_TEXTURE)
	local yield=options.yield
	local image=ENGINES[kind].decode(source,{yield=yield,maxSize=limit})
	assert(type(image)=="table" and typeof(image.pixels)=="buffer","Falha ao decodificar a imagem.")
	assert(image.width>=1 and image.height>=1 and buffer.len(image.pixels)==image.width*image.height*4,"Decodificacao inconsistente.")
	image.format=kind
	image.sourceWidth=image.sourceWidth or image.width
	image.sourceHeight=image.sourceHeight or image.height
	local targetWidth,targetHeight=image.width,image.height
	if options.width and options.height then
		targetWidth=math.clamp(math.floor(options.width),1,Limits.MAX_TEXTURE)
		targetHeight=math.clamp(math.floor(options.height),1,Limits.MAX_TEXTURE)
	elseif image.width>limit or image.height>limit then
		local factor=math.min(limit/image.width,limit/image.height)
		targetWidth=math.max(1,math.floor(image.width*factor+0.5))
		targetHeight=math.max(1,math.floor(image.height*factor+0.5))
	end
	if targetWidth~=image.width or targetHeight~=image.height then
		local scaled=Resample.scale(image,targetWidth,targetHeight,{yield=yield})
		scaled.format=kind
		scaled.sourceWidth=image.sourceWidth
		scaled.sourceHeight=image.sourceHeight
		scaled.resized=true
		image=scaled
	end
	return image
end

return table.freeze(ImageDecode)
