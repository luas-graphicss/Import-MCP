local Apply={}

local IMAGE_PROPERTIES={
	{class="ImageLabel",property="ImageContent"},
	{class="ImageButton",property="ImageContent"},
	{class="Decal",property="TextureContent"},
	{class="MeshPart",property="TextureContent"},
	{class="ParticleEmitter",property="TextureContent"},
	{class="Beam",property="TextureContent"},
	{class="Trail",property="TextureContent"},
	{class="SurfaceAppearance",property="ColorMapContent"},
}

Apply.IMAGE_CLASSES=table.freeze({"ImageLabel","ImageButton","Decal","Texture","MeshPart","ParticleEmitter","Beam","Trail","SurfaceAppearance"})

local function readable(instance,property)
	return pcall(function() return instance[property] end)
end

function Apply.imageProperty(instance)
	for _,entry in ipairs(IMAGE_PROPERTIES) do
		if instance:IsA(entry.class) and readable(instance,entry.property) then
			return entry.property
		end
	end
	return nil
end

function Apply.acceptsImage(instance)
	return Apply.imageProperty(instance)~=nil
end

function Apply.image(instance,content)
	assert(typeof(content)=="Content","Content de imagem invalido.")
	local property=Apply.imageProperty(instance)
	assert(property,"A classe "..instance.ClassName.." nao aceita imagem via Content.")
	instance[property]=content
	return property
end

function Apply.mesh(target,fresh)
	assert(target:IsA("MeshPart") and fresh:IsA("MeshPart"),"Apply.mesh requer MeshParts.")
	local cframe,size,pivot=target.CFrame,target.Size,target.PivotOffset
	local doubleSided,fidelity=target.DoubleSided,target.RenderFidelity
	target:ApplyMesh(fresh)
	target.TextureContent=fresh.TextureContent
	target.CFrame=cframe
	target.Size=size
	target.PivotOffset=pivot
	target.DoubleSided=doubleSided
	target.RenderFidelity=fidelity
end

return table.freeze(Apply)
