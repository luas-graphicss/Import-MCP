local Limits=require(script.Parent.Parent.Runtime.Limits)

return table.freeze({
	NAME="ImportMCP",
	VERSION="1.0.0",
	RUNTIME_VERSION=Limits.RUNTIME_VERSION,
	STAGING="ImportMCP_Staging",
	STAGING_TTL=3600,
	DEFAULT_SCREEN_GUI="ImportMCP",
	DEFAULT_IMAGE_CLASS="ImageLabel",
	DEFAULT_MODEL_CLASS="Model",
	DEFAULT_GUI_SIZE=256,
	IMAGE_CLASSES=table.freeze({ImageLabel=true,ImageButton=true,Decal=true,Texture=true}),
	MODEL_CLASSES=table.freeze({Model=true,MeshPart=true}),
	FORMATS=table.freeze({png="image",jpeg="image",glb="model",gltf="model"}),
	EXTENSIONS=table.freeze({"png","jpg","jpeg","glb","gltf","bin"}),
	MAX_BYTES=Limits.MAX_SOURCE_BYTES,
	MAX_TEXTURE=Limits.MAX_TEXTURE,
})
