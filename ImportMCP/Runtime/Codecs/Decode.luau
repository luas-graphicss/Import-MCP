local Png=require(script.Parent.Png)
local Jpeg=require(script.Parent.Jpeg)

local Decode={}

local ENGINES={png=Png,jpeg=Jpeg}

function Decode.kind(source)
	if type(source)=="string" then source=buffer.fromstring(source) end
	if typeof(source)~="buffer" then return nil end
	if Png.matches(source) then return "png" end
	if Jpeg.matches(source) then return "jpeg" end
	return nil
end

function Decode.matches(source)
	return Decode.kind(source)~=nil
end

function Decode.fromName(name)
	local lowered=string.lower(tostring(name))
	if string.sub(lowered,-4)==".png" then return "png" end
	if string.sub(lowered,-4)==".jpg" or string.sub(lowered,-5)==".jpeg" or string.sub(lowered,-4)==".jpe" then return "jpeg" end
	return nil
end

function Decode.extensions()
	return {"png","jpg","jpeg"}
end

function Decode.decode(source,options)
	if type(source)=="string" then source=buffer.fromstring(source) end
	if typeof(source)~="buffer" then error("Conteudo de imagem invalido.",0) end
	if buffer.len(source)<16 then error("Arquivo de imagem vazio ou truncado.",0) end
	local kind=Decode.kind(source)
	if not kind then error("Formato de imagem nao reconhecido; use PNG ou JPEG.",0) end
	local image=ENGINES[kind].decode(source,options)
	if type(image)~="table" or typeof(image.pixels)~="buffer" then error("Falha ao decodificar a imagem.",0) end
	if image.width<1 or image.height<1 or buffer.len(image.pixels)~=image.width*image.height*4 then error("Decodificacao de imagem inconsistente.",0) end
	image.format=image.format or kind
	return image
end

return Decode
