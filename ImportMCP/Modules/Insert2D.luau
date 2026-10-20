local Config=require(script.Parent.Config)
local Runtime=script.Parent.Parent.Runtime
local Image=require(Runtime.Build.Image)
local Apply=require(Runtime.Build.Apply)

local Insert2D={}

local function udim2(value,fallback)
	if typeof(value)=="UDim2" then return value end
	if type(value)=="table" then
		if #value==4 then return UDim2.new(value[1],value[2],value[3],value[4]) end
		if #value==2 then return UDim2.fromOffset(value[1],value[2]) end
		if value.scaleX or value.offsetX or value.scaleY or value.offsetY then
			return UDim2.new(value.scaleX or 0,value.offsetX or 0,value.scaleY or 0,value.offsetY or 0)
		end
		if value.width or value.height then
			return UDim2.fromOffset(value.width or fallback.X.Offset,value.height or fallback.Y.Offset)
		end
	end
	return fallback
end

local function vector2(value,fallback)
	if typeof(value)=="Vector2" then return value end
	if type(value)=="table" and #value==2 then return Vector2.new(value[1],value[2]) end
	return fallback
end

local function fitSize(image)
	local longest=math.max(image.width,image.height)
	local factor=math.min(1,Config.DEFAULT_GUI_SIZE/longest)
	return UDim2.fromOffset(math.max(1,math.floor(image.width*factor+0.5)),math.max(1,math.floor(image.height*factor+0.5)))
end

local function applyProps(instance,props,warnings)
	if type(props)~="table" then return end
	for key,value in pairs(props) do
		local ok,err=pcall(function() instance[key]=value end)
		if not ok then warnings[#warnings+1]="Propriedade '"..tostring(key).."' ignorada: "..tostring(err):match("^[^\n]+") end
	end
end

function Insert2D.create(className,parent,image,options,warnings)
	local instance=Instance.new(className)
	instance.Name=options.name
	if instance:IsA("GuiObject") then
		instance.BackgroundTransparency=1
		instance.BorderSizePixel=0
		instance.Size=udim2(options.size,fitSize(image))
		instance.AnchorPoint=vector2(options.anchor,Vector2.new(0.5,0.5))
		instance.Position=udim2(options.position,UDim2.fromScale(0.5,0.5))
		if options.zIndex then instance.ZIndex=options.zIndex end
		pcall(function() instance.ScaleType=Enum.ScaleType[options.scaleType or "Fit"] end)
		pcall(function() instance.Active=false end)
	elseif instance:IsA("Decal") then
		local face=options.face and Enum.NormalId[options.face] or Enum.NormalId.Front
		instance.Face=face
		if instance:IsA("Texture") then
			if options.studsPerTile then
				instance.StudsPerTileU=options.studsPerTile
				instance.StudsPerTileV=options.studsPerTile
			end
		end
	end
	applyProps(instance,options.props,warnings)
	instance.Parent=parent
	return instance
end

function Insert2D.import(bytes,parent,options)
	local warnings={}
	local content,image=Image.fromBytes(bytes,{maxSize=options.maxSize,yield=options.yield,check=options.check})
	local instance
	local property
	if options.applyTo then
		instance=options.applyTo
		property=Apply.image(instance,content)
	else
		instance=Insert2D.create(options.className,parent,image,options,warnings)
		property=Apply.image(instance,content)
	end
	if image.resized then
		warnings[#warnings+1]="Imagem reduzida de "..image.sourceWidth.."x"..image.sourceHeight.." para "..image.width.."x"..image.height.." (limite "..Config.MAX_TEXTURE..")."
	end
	return {
		instance=instance,
		property=property,
		width=image.width,
		height=image.height,
		sourceWidth=image.sourceWidth,
		sourceHeight=image.sourceHeight,
		format=image.format,
		hasAlpha=image.hasAlpha,
		warnings=warnings,
	}
end

return table.freeze(Insert2D)
