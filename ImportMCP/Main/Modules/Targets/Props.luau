local Props={}

local function num(value,default)
	local number=tonumber(value)
	if number==nil or number~=number then return default or 0 end
	return number
end

local function color(value)
	if typeof(value)=="Color3" then return value end
	if type(value)=="string" then
		local hex=value:gsub("^#","")
		if #hex==3 then hex=hex:gsub(".",function(c) return c..c end) end
		if #hex==6 then return Color3.fromRGB(tonumber(hex:sub(1,2),16),tonumber(hex:sub(3,4),16),tonumber(hex:sub(5,6),16)) end
		local ok,brick=pcall(BrickColor.new,value)
		if ok then return brick.Color end
	end
	if type(value)=="table" then
		local r,g,b=num(value[1] or value.r or value.R),num(value[2] or value.g or value.G),num(value[3] or value.b or value.B)
		if r>1 or g>1 or b>1 then return Color3.fromRGB(math.clamp(r,0,255),math.clamp(g,0,255),math.clamp(b,0,255)) end
		return Color3.new(math.clamp(r,0,1),math.clamp(g,0,1),math.clamp(b,0,1))
	end
	error("Cor invalida.")
end

local function vector3(value)
	if typeof(value)=="Vector3" then return value end
	if type(value)=="table" then return Vector3.new(num(value[1] or value.x or value.X),num(value[2] or value.y or value.Y),num(value[3] or value.z or value.Z)) end
	error("Vector3 invalido.")
end

local function vector2(value)
	if typeof(value)=="Vector2" then return value end
	if type(value)=="table" then return Vector2.new(num(value[1] or value.x or value.X),num(value[2] or value.y or value.Y)) end
	error("Vector2 invalido.")
end

local function udim(value)
	if typeof(value)=="UDim" then return value end
	if type(value)=="number" then return UDim.new(0,value) end
	if type(value)=="table" then return UDim.new(num(value[1] or value.scale or value.Scale),num(value[2] or value.offset or value.Offset)) end
	error("UDim invalido.")
end

local function udim2(value)
	if typeof(value)=="UDim2" then return value end
	if type(value)=="table" then
		if value.x~=nil or value.X~=nil then return UDim2.new(udim(value.x or value.X),udim(value.y or value.Y)) end
		if #value==4 then return UDim2.new(num(value[1]),num(value[2]),num(value[3]),num(value[4])) end
		if #value==2 then
			if type(value[1])=="table" then return UDim2.new(udim(value[1]),udim(value[2])) end
			return UDim2.fromOffset(num(value[1]),num(value[2]))
		end
	end
	error("UDim2 invalido.")
end

local function cframe(value)
	if typeof(value)=="CFrame" then return value end
	if type(value)=="table" then
		local position=vector3(value.position or value)
		local orientation=value.orientation or value.rotation
		if #value==6 then orientation={value[4],value[5],value[6]} end
		if orientation then
			local o=vector3(orientation)
			return CFrame.new(position)*CFrame.fromOrientation(math.rad(o.X),math.rad(o.Y),math.rad(o.Z))
		end
		return CFrame.new(position)
	end
	error("CFrame invalido.")
end

local function enumValue(current,value)
	if typeof(value)=="EnumItem" then return value end
	local enumType=current.EnumType
	local text=tostring(value):gsub("^Enum%.[%w_]+%.","")
	local ok,item=pcall(function() return enumType[text] end)
	if ok and item then return item end
	local number=tonumber(value)
	if number then
		for _,candidate in ipairs(enumType:GetEnumItems()) do
			if candidate.Value==number then return candidate end
		end
	end
	error("Valor de enum invalido: "..tostring(value))
end

local CONVERTERS={Color3=color,Vector3=vector3,Vector2=vector2,UDim=udim,UDim2=udim2,CFrame=cframe,EnumItem=enumValue,BrickColor=function(value) return BrickColor.new(color(value)) end}

Props.convert=function(instance,key,value)
	local current=instance[key]
	local kind=typeof(current)
	if kind=="number" then return num(value) end
	if kind=="boolean" then
		if type(value)=="string" then return value:lower()=="true" end
		return value and true or false
	end
	if kind=="string" then return tostring(value) end
	local converter=CONVERTERS[kind]
	if converter then
		if kind=="EnumItem" then return converter(current,value) end
		return converter(value)
	end
	if kind=="Instance" or kind=="nil" then
		if type(value)=="string" then return require(script.Parent.Resolve).optional(value) end
	end
	return value
end

function Props.apply(instance,properties)
	local applied,failed={},{}
	if type(properties)~="table" then return applied,failed end
	for key,value in pairs(properties) do
		local ok,err=pcall(function()
			instance[key]=Props.convert(instance,key,value)
		end)
		if ok then applied[#applied+1]=key else failed[#failed+1]=key..": "..tostring(err):match("^[^\n]+") end
	end
	return applied,failed
end

function Props.position(value)
	if value==nil then return nil end
	return cframe(value)
end

return table.freeze(Props)
