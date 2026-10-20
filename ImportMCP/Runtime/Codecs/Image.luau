local Decode=require(script.Parent.Decode)
local Resample=require(script.Parent.Resample)

local Image={}

local MAX_BYTES=64*1024*1024
local MAX_SIZE=1024

function Image.extensions()
	return Decode.extensions()
end

function Image.maxBytes()
	return MAX_BYTES
end

function Image.maxSize()
	return MAX_SIZE
end

function Image.matches(source)
	return Decode.matches(source)
end

function Image.kind(name)
	return Decode.fromName(name)
end

function Image.name(raw)
	local text=tostring(raw or "")
	text=string.match(text,"([^/\\]+)$") or text
	text=string.gsub(text,"^%s+","")
	text=string.gsub(text,"%s+$","")
	if text=="" then text="imagem" end
	if #text>48 then text=string.sub(text,1,48) end
	return text
end

local function pixelsOf(value)
	if type(value)=="table" then value=value.pixels end
	if typeof(value)~="buffer" then error("Falha ao redimensionar a imagem.",0) end
	return value
end

function Image.decode(contents,options)
	options=options or {}
	if type(contents)=="string" then
		if #contents==0 then error("Arquivo de imagem vazio.",0) end
		if #contents>MAX_BYTES then error("Arquivo de imagem acima de 64 MB.",0) end
		contents=buffer.fromstring(contents)
	end
	if typeof(contents)~="buffer" then error("Conteudo de imagem invalido.",0) end
	if buffer.len(contents)>MAX_BYTES then error("Arquivo de imagem acima de 64 MB.",0) end
	local limit=math.floor(tonumber(options.maxSize) or MAX_SIZE)
	if limit<16 then limit=16 end
	if limit>MAX_SIZE then limit=MAX_SIZE end
	local yield=options.yield
	local image=Decode.decode(contents,{yield=yield,maxSize=limit})
	local sourceWidth=image.sourceWidth or image.width
	local sourceHeight=image.sourceHeight or image.height
	if image.width>limit or image.height>limit then
		local factor=math.min(limit/image.width,limit/image.height)
		local width=math.max(1,math.min(limit,math.floor(image.width*factor+0.5)))
		local height=math.max(1,math.min(limit,math.floor(image.height*factor+0.5)))
		image.pixels=pixelsOf(Resample.scale(image,width,height,{yield=yield}))
		image.width=width
		image.height=height
	end
	if image.width<1 or image.height<1 or buffer.len(image.pixels)~=image.width*image.height*4 then
		error("Imagem decodificada inconsistente.",0)
	end
	image.sourceWidth=sourceWidth
	image.sourceHeight=sourceHeight
	image.resized=(sourceWidth~=image.width or sourceHeight~=image.height)
	return image
end

function Image.fit(image,width,height,options)
	options=options or {}
	if width<1 or height<1 or width>MAX_SIZE or height>MAX_SIZE then error("Tamanho de textura invalido.",0) end
	if image.width==width and image.height==height then return image end
	local pixels=pixelsOf(Resample.scale(image,width,height,{yield=options.yield}))
	return {width=width,height=height,pixels=pixels,format=image.format,hasAlpha=image.hasAlpha,
		sourceWidth=image.sourceWidth or image.width,sourceHeight=image.sourceHeight or image.height,resized=true}
end

function Image.describe(image)
	local text=string.upper(tostring(image.format or "imagem")).." "..image.width.."x"..image.height
	if image.resized then
		text=text.." (original "..(image.sourceWidth or image.width).."x"..(image.sourceHeight or image.height)..")"
	end
	if image.hasAlpha then text=text.." com alfa" end
	return text
end

return Image
