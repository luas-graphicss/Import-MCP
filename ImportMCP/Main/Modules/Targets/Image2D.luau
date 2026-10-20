local Runtime=script.Parent.Parent.Runtime
local ImageDecode=require(Runtime.ImageDecode)
local ImageBuild=require(Runtime.ImageBuild)
local Materialize=require(Runtime.Materialize)
local Resolve=require(script.Parent.Resolve)
local Props=require(script.Parent.Props)
local Persist=require(script.Parent.Persist)
local StarterGui=game:GetService("StarterGui")

local Image2D={}

local GUI_CLASSES={ImageLabel=true,ImageButton=true}
local WORLD_CLASSES={Decal=true,Texture=true}
local MAX_PREVIEW=400

Image2D.classes={"ImageLabel","ImageButton","Decal","Texture"}

local function createInstance(class,name,target,info)
	assert(GUI_CLASSES[class] or WORLD_CLASSES[class],"Classe 2D nao suportada: "..tostring(class)..". Use ImageLabel, ImageButton, Decal, Texture ou target.applyTo.")
	local parent
	if GUI_CLASSES[class] then
		parent=Resolve.guiParent(Resolve.parent(target.parent,StarterGui))
	else
		parent=Resolve.parent(target.parent,nil)
		assert(parent and parent:IsA("BasePart"),class.." precisa de um BasePart em target.parent.")
	end
	local instance=Instance.new(class)
	instance.Name=Resolve.uniqueName(parent,name)
	if GUI_CLASSES[class] then
		instance.BackgroundTransparency=1
		instance.BorderSizePixel=0
		instance.ScaleType=Enum.ScaleType.Fit
		local factor=math.min(1,MAX_PREVIEW/math.max(info.width,info.height))
		instance.Size=UDim2.fromOffset(math.round(info.width*factor),math.round(info.height*factor))
		instance.AnchorPoint=Vector2.new(0.5,0.5)
		instance.Position=UDim2.fromScale(0.5,0.5)
	else
		instance.Face=Enum.NormalId.Front
	end
	return instance,parent
end

function Image2D.import(job,ctx)
	ctx=ctx or {}
	local target=job.target or {}
	local bytes=job.bytes
	assert(typeof(bytes)=="buffer","Bytes da imagem ausentes.")
	local kind=ImageDecode.kind(bytes)
	assert(kind,"Arquivo nao e PNG nem JPEG.")
	local mode=Materialize.mode(job.persist)
	if ctx.stage then ctx.stage("decodificando") end
	local image=ImageDecode.decode(bytes,{yield=ctx.yield,maxSize=target.maxSize})
	if ctx.check then ctx.check() end
	if ctx.stage then ctx.stage("construindo") end
	local content,info=ImageBuild.content(image,{check=ctx.check,stage=ctx.stage,mode=mode,fallback=job.fallback~=false,name=job.name})
	local instance,parent,created
	if target.applyTo then
		instance=Resolve.instance(target.applyTo,false)
		created=false
	else
		instance,parent=createInstance(target.class or "ImageLabel",job.name,target,info)
		created=true
	end
	local property=target.property or ImageBuild.property(instance)
	assert(property,"A instancia "..instance.ClassName.." nao aceita conteudo de imagem; informe target.property.")
	ImageBuild.apply(instance,content,property)
	local applied,failed=Props.apply(instance,target.properties)
	if created then instance.Parent=parent end
	local meta={Property=property,Width=info.width,Height=info.height,SourceWidth=info.sourceWidth,SourceHeight=info.sourceHeight,Source=job.fileName,MaxSize=target.maxSize}
	local usedMode=info.mode
	if usedMode=="asset" then
		Materialize.mark(instance,"Image",{info.assetId},meta)
	elseif mode~=false then
		if ctx.stage then ctx.stage("persistindo") end
		Persist.attach(instance,"Image",bytes,"IMG1",meta,ctx.yield)
	else
		usedMode="none"
	end
	return instance,{kind="Image",format=kind,width=info.width,height=info.height,sourceWidth=info.sourceWidth,sourceHeight=info.sourceHeight,resized=info.resized,property=property,created=created,propertiesApplied=applied,propertiesFailed=failed,persisted=usedMode~="none",mode=usedMode,requestedMode=mode or "none",assetId=info.assetId,assetIds=info.assetId and {info.assetId} or {},fallback=info.fallback}
end

return table.freeze(Image2D)
