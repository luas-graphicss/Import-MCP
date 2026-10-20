local Config=require(script.Parent.Config)

local Log={}

local function line(value)
	return tostring(value):match("^[^\n]+") or tostring(value)
end

function Log.info(message)
	print(Config.NAME..": "..tostring(message))
end

function Log.warn(message)
	warn(Config.NAME..": "..line(message))
end

function Log.firstLine(value)
	return line(value)
end

return table.freeze(Log)
