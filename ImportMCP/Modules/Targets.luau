local Config=require(script.Parent.Config)
local Apply=require(script.Parent.Parent.Runtime.Build.Apply)

local Targets={}

function Targets.resolve(path)
	if path==nil or path=="" then return nil end
	if typeof(path)=="Instance" then return path end
	local text=tostring(path)
	text=text:gsub("^game[%./]",""):gsub("/",".")
	local current=game
	for segment in text:gmatch("[^%.]+") do
		local nextInstance=nil
		if current==game then
			local ok,service=pcall(game.GetService,game,segment)
			if ok and typeof(service)=="Instance" then nextInstance=service end
		end
		nextInstance=nextInstance or current:FindFirstChild(segment)
		assert(nextInstance,"Alvo nao encontrado: '"..segment.."' em "..current:GetFullName())
		current=nextInstance
	end
	return current
end

function Targets.defaultParent(kind)
	if kind=="image" then return game:GetService("StarterGui") end
	return workspace
end

function Targets.className(kind,requested)
	if requested==nil or requested=="" or requested=="auto" then
		return kind=="image" and Config.DEFAULT_IMAGE_CLASS or Config.DEFAULT_MODEL_CLASS
	end
	local name=tostring(requested)
	if kind=="image" then
		assert(Config.IMAGE_CLASSES[name],"Classe 2D nao suportada: "..name..". Use ImageLabel, ImageButton, Decal ou Texture.")
	else
		assert(Config.MODEL_CLASSES[name],"Classe 3D nao suportada: "..name..". Use Model ou MeshPart.")
	end
	return name
end

local function screenGui(parent)
	local existing=parent:FindFirstChild(Config.DEFAULT_SCREEN_GUI)
	if existing and existing:IsA("LayerCollector") then return existing end
	local gui=Instance.new("ScreenGui")
	gui.Name=Config.DEFAULT_SCREEN_GUI
	gui.ResetOnSpawn=false
	gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
	gui.Parent=parent
	return gui
end

function Targets.parentFor(kind,className,target)
	local parent=target or Targets.defaultParent(kind)
	if kind=="image" then
		if className=="Decal" or className=="Texture" then
			assert(parent:IsA("BasePart"),"Decal/Texture precisam de um BasePart como alvo; recebido "..parent.ClassName..".")
			return parent
		end
		if parent:IsA("StarterGui") or parent:IsA("PlayerGui") then
			return screenGui(parent)
		end
		assert(parent:IsA("GuiBase2d") or parent:IsA("LayerCollector"),"ImageLabel/ImageButton precisam de um ScreenGui, SurfaceGui, BillboardGui ou GuiObject como alvo; recebido "..parent.ClassName..".")
		return parent
	end
	assert(parent~=game,"Alvo 3D invalido.")
	return parent
end

function Targets.acceptsImage(instance)
	return Apply.acceptsImage(instance)
end

return table.freeze(Targets)
