local Resolve={}

local function segments(path)
	local text=tostring(path):gsub("^%s+",""):gsub("%s+$","")
	text=text:gsub("^game[%./]",""):gsub("^game$","")
	local out={}
	for segment in text:gmatch("[^%./]+") do out[#out+1]=segment end
	return out
end

function Resolve.instance(path,create)
	if typeof(path)=="Instance" then return path end
	assert(type(path)=="string" and #path>0,"Caminho de instancia invalido.")
	local current=game
	for _,segment in ipairs(segments(path)) do
		local found
		if current==game then
			local ok,service=pcall(game.GetService,game,segment)
			if ok and typeof(service)=="Instance" then found=service end
		end
		found=found or current:FindFirstChild(segment)
		if not found then
			assert(create,"Caminho nao encontrado: '"..segment.."' em "..current:GetFullName()..".")
			found=Instance.new("Folder")
			found.Name=segment
			found.Parent=current
		end
		current=found
	end
	assert(current~=game,"Informe um caminho abaixo de game.")
	return current
end

function Resolve.optional(path)
	if path==nil or path=="" then return nil end
	return Resolve.instance(path,false)
end

function Resolve.parent(path,default)
	if path==nil or path=="" then return default end
	return Resolve.instance(path,true)
end

function Resolve.guiParent(parent)
	if parent:IsA("LayerCollector") or parent:IsA("GuiBase2d") then return parent end
	if parent:FindFirstAncestorWhichIsA("LayerCollector") then return parent end
	local gui=parent:FindFirstChild("ImportMCP")
	if not gui or not gui:IsA("ScreenGui") then
		gui=Instance.new("ScreenGui")
		gui.Name="ImportMCP"
		gui.ResetOnSpawn=false
		gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
		gui.Parent=parent
	end
	return gui
end

function Resolve.uniqueName(parent,name)
	name=tostring(name or "Asset"):gsub("[%c]",""):sub(1,100)
	if name=="" then name="Asset" end
	if not parent:FindFirstChild(name) then return name end
	local index=2
	while parent:FindFirstChild(name.."_"..index) do index+=1 end
	return name.."_"..index
end

function Resolve.baseName(fileName,fallback)
	local text=tostring(fileName or fallback or "Asset")
	text=text:match("([^/\\]+)$") or text
	text=text:gsub("%.[%w]+$","")
	text=text:gsub("^%s+",""):gsub("%s+$","")
	if text=="" then text=fallback or "Asset" end
	return text:sub(1,100)
end

return table.freeze(Resolve)
