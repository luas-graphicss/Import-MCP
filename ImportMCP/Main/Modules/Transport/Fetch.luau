local Runtime=script.Parent.Parent.Runtime
local Limits=require(Runtime.Limits)
local HttpService=game:GetService("HttpService")

local Fetch={}

function Fetch.bytes(url,options)
	options=options or {}
	assert(type(url)=="string" and url:match("^https?://"),"URL invalida; use http(s)://.")
	local ok,response=pcall(function()
		return HttpService:RequestAsync({Url=url,Method="GET",Headers=options.headers or {}})
	end)
	assert(ok,"Falha de rede ao baixar "..url..": "..tostring(response).." (HttpService precisa estar habilitado em Game Settings > Security).")
	assert(response.Success,"HTTP "..tostring(response.StatusCode).." ao baixar "..url..".")
	local body=response.Body
	assert(type(body)=="string" and #body>0,"Resposta vazia de "..url..".")
	local maxBytes=tonumber(options.maxBytes) or Limits.MAX_BYTES
	assert(#body<=maxBytes,"Arquivo acima de "..(maxBytes//1048576).." MiB.")
	 
	local name
	local headers=response.Headers or {}
	local disposition=headers["content-disposition"] or headers["Content-Disposition"]
	if type(disposition)=="string" then
		name=disposition:match("filename%*=[Uu][Tt][Ff]%-8''([^;]+)") or disposition:match('filename="([^"]+)"') or disposition:match("filename=([^;%s]+)")
	end
	name=name or url:gsub("[?#].*$",""):match("([^/]+)$") or "download"
	name=name:gsub("%%(%x%x)",function(hex) return string.char(tonumber(hex,16)) end):gsub("[%c\"'\\/]",""):sub(1,120)
	if name=="" then name="download" end
	return buffer.fromstring(body),name,headers
end

return table.freeze(Fetch)
