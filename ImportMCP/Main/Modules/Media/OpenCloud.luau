local Limits=require(script.Parent.Parent.Runtime.Limits)
local HttpService=game:GetService("HttpService")

 
 
 
local OpenCloud={}

OpenCloud.ASSETS_URL="https://apis.roblox.com/assets/v1/assets"
OpenCloud.OPERATIONS_URL="https://apis.roblox.com/assets/v1/operations/"

local settings={apiKey=nil,creator=nil}

local ASSET_TYPES={audio="Audio",video="Video"}

local function firstLine(err)
	return tostring(err):match("^[^\n]+") or tostring(err)
end

 
function OpenCloud.creator(value)
	if type(value)=="string" then
		local kind,id=value:match("^(%a+):(%d+)$")
		if kind then
			if string.lower(kind)=="group" then return {groupId=id} end
			return {userId=id}
		end
		if value:match("^%d+$") then return {userId=value} end
	elseif type(value)=="table" then
		if value.groupId then return {groupId=tostring(value.groupId)} end
		if value.userId then return {userId=tostring(value.userId)} end
	end
	if settings.creator then return settings.creator end
	if game.CreatorType==Enum.CreatorType.Group and game.CreatorId>0 then return {groupId=tostring(game.CreatorId)} end
	local userId=0
	pcall(function() userId=game:GetService("StudioService"):GetUserId() end)
	if userId==0 and game.CreatorType==Enum.CreatorType.User then userId=game.CreatorId end
	assert(userId>0,"Nao foi possivel identificar o criador; informe openCloud.creator={userId=...} ou {groupId=...}.")
	return {userId=tostring(userId)}
end

function OpenCloud.configure(options)
	options=options or {}
	if options.apiKey~=nil then
		assert(options.apiKey==false or (type(options.apiKey)=="string" and #options.apiKey>=16),"Chave de API Open Cloud invalida.")
		settings.apiKey=options.apiKey or nil
	end
	if options.creator~=nil then
		settings.creator=options.creator~=false and OpenCloud.creator(options.creator) or nil
	end
	return OpenCloud.status()
end

function OpenCloud.status()
	local okCreator,creator=pcall(OpenCloud.creator,nil)
	return {configured=settings.apiKey~=nil,keyPreview=settings.apiKey and (settings.apiKey:sub(1,6).."...") or nil,creator=okCreator and creator or nil}
end

function OpenCloud.apiKey(override)
	if type(override)=="string" and #override>0 then return override end
	return settings.apiKey
end

local function classify(statusCode,body)
	local text=tostring(body or "")
	if statusCode==401 then return "unauthorized","Chave de API recusada (401). Confira a chave em create.roblox.com/dashboard/credentials e a permissao 'Assets: Read & Write'." end
	if statusCode==403 then return "forbidden","Acesso negado (403): a chave nao tem permissao de Assets para este criador, o IP nao esta na lista da chave, ou a conta nao pode publicar este tipo de asset. "..text:sub(1,300) end
	if statusCode==429 then return "rate","Limite de uploads atingido (429). Aguarde e tente de novo. "..text:sub(1,200) end
	if statusCode==400 then return "invalid","Pedido rejeitado (400): "..text:sub(1,400) end
	return "failed","HTTP "..tostring(statusCode)..": "..text:sub(1,400)
end

local function request(options,check)
	local ok,response=pcall(HttpService.RequestAsync,HttpService,options)
	if check then check() end
	if not ok then
		local text=firstLine(response)
		local lowered=string.lower(text)
		if lowered:find("not allowed") or lowered:find("not permitted") or lowered:find("trust") or lowered:find("blocked") or lowered:find("denied") then
			error({code="blocked",message="O acesso HTTP a apis.roblox.com foi bloqueado ("..text.."). Libere o dominio nas permissoes HTTP do plugin que fez a chamada (Plugins > Manage Plugins: ImportMCP ou o plugin do MCP); se o Studio nao permitir, faca o upload pela Open Cloud fora do Studio (agente/CLI) e importe com assetId, ou envie pelo Creator Hub."},0)
		end
		if lowered:find("http requests are not enabled") or lowered:find("httpenabled") then
			error({code="http",message="Habilite 'Allow HTTP Requests' em Game Settings > Security para usar a Open Cloud."},0)
		end
		error({code="network",message="Falha de rede na Open Cloud: "..text},0)
	end
	return response
end

local function multipart(meta,bytes,fileName,mime)
	local boundary="ImportMCP"..HttpService:GenerateGUID(false):gsub("-","")
	local parts={
		"--"..boundary.."\r\n",
		'Content-Disposition: form-data; name="request"\r\n',
		"Content-Type: application/json\r\n\r\n",
		HttpService:JSONEncode(meta),
		"\r\n--"..boundary.."\r\n",
		string.format('Content-Disposition: form-data; name="fileContent"; filename="%s"\r\n',fileName),
		"Content-Type: "..mime.."\r\n\r\n",
		buffer.tostring(bytes),
		"\r\n--"..boundary.."--\r\n",
	}
	return table.concat(parts),boundary
end

local function sanitizeName(name)
	local clean=tostring(name or "Midia"):gsub("%.%w+$",""):gsub("[^%w%s_%-]","_"):gsub("%s+"," ")
	clean=clean:match("^%s*(.-)%s*$") or clean
	if #clean==0 then clean="Midia" end
	return clean:sub(1,50)
end

local function decode(body)
	local ok,data=pcall(HttpService.JSONDecode,HttpService,body)
	return ok and type(data)=="table" and data or {}
end

 
function OpenCloud.wait(operationId,apiKey,options)
	options=options or {}
	local check=options.check
	local deadline=os.clock()+(options.timeout or Limits.UPLOAD_POLL_TIMEOUT)
	local delay=1
	while true do
		local response=request({Url=OpenCloud.OPERATIONS_URL..operationId,Method="GET",Headers={["x-api-key"]=apiKey}},check)
		if response.Success then
			local data=decode(response.Body)
			if data.done then
				if type(data.error)=="table" then
					error({code="failed",message="Upload falhou: "..tostring(data.error.message or data.error.code or response.Body):sub(1,400)},0)
				end
				local payload=type(data.response)=="table" and data.response or {}
				local assetId=tonumber(payload.assetId) or tonumber(tostring(payload.path or ""):match("assets/(%d+)"))
				assert(assetId,"Operacao concluida sem assetId: "..tostring(response.Body):sub(1,300))
				return assetId,payload
			end
		elseif response.StatusCode~=404 and response.StatusCode~=429 then
			local code,message=classify(response.StatusCode,response.Body)
			error({code=code,message="Consulta da operacao falhou: "..message},0)
		end
		if options.stage then options.stage("processando") end
		if os.clock()>=deadline then
			error({code="processing",operationId=operationId,message="A Roblox ainda esta processando o upload (operacao "..operationId.."). A midia fica pendente com a operacao registrada; Api.media.upload(path) conclui sem reenviar o arquivo."},0)
		end
		task.wait(delay)
		if check then check() end
		delay=math.min(delay*1.5,8)
	end
end

 
 
function OpenCloud.upload(bytes,options)
	options=options or {}
	assert(typeof(bytes)=="buffer" and buffer.len(bytes)>0,"Bytes da midia ausentes.")
	local assetType=ASSET_TYPES[options.kind]
	assert(assetType,"Tipo de midia invalido para a Open Cloud: use audio ou video.")
	local apiKey=OpenCloud.apiKey(options.apiKey)
	assert(apiKey,"Sem chave Open Cloud: use Api.setOpenCloud{apiKey='...'} (Creator Hub > Credenciais, permissao Assets: Read & Write) ou passe openCloud={apiKey=...} na requisicao.")
	local creator=OpenCloud.creator(options.creator)
	local meta={assetType=assetType,displayName=sanitizeName(options.name),description=tostring(options.description or "Importado pelo ImportMCP"):sub(1,1000),creationContext={creator=creator}}
	local fileName=tostring(options.fileName or (meta.displayName.."."..(options.ext or "bin"))):gsub("[\"\r\n]","")
	local body,boundary=multipart(meta,bytes,fileName,options.mime or "application/octet-stream")
	if options.stage then options.stage("enviando") end
	local response=request({Url=OpenCloud.ASSETS_URL,Method="POST",Headers={["x-api-key"]=apiKey,["Content-Type"]="multipart/form-data; boundary="..boundary},Body=body},options.check)
	if not response.Success then
		local code,message=classify(response.StatusCode,response.Body)
		error({code=code,message=message},0)
	end
	local data=decode(response.Body)
	local operationId=data.operationId or tostring(data.path or ""):match("operations/([%w%-]+)")
	local result={operationId=operationId,name=meta.displayName,creator=creator}
	if data.done and type(data.response)=="table" then
		result.assetId=tonumber(data.response.assetId) or tonumber(tostring(data.response.path or ""):match("assets/(%d+)"))
	end
	if not result.assetId then
		assert(operationId,"Resposta inesperada da Open Cloud: "..tostring(response.Body):sub(1,300))
		if options.wait==false then return result end
		result.assetId=OpenCloud.wait(operationId,apiKey,{check=options.check,stage=options.stage,timeout=options.timeout})
	end
	return result
end

 
function OpenCloud.operation(operationId,apiKey)
	apiKey=OpenCloud.apiKey(apiKey)
	assert(apiKey,"Sem chave Open Cloud configurada.")
	local response=request({Url=OpenCloud.OPERATIONS_URL..tostring(operationId),Method="GET",Headers={["x-api-key"]=apiKey}})
	if not response.Success then
		local code,message=classify(response.StatusCode,response.Body)
		return {ok=false,code=code,error=message}
	end
	local data=decode(response.Body)
	local payload=type(data.response)=="table" and data.response or {}
	return {ok=true,done=data.done==true,assetId=tonumber(payload.assetId) or tonumber(tostring(payload.path or ""):match("assets/(%d+)")),error=type(data.error)=="table" and tostring(data.error.message or data.error.code) or nil,raw=data}
end

function OpenCloud.errorText(err)
	if type(err)=="table" then return tostring(err.message or err.code) end
	return firstLine(err)
end

function OpenCloud.errorCode(err)
	return type(err)=="table" and err.code or nil
end

return table.freeze(OpenCloud)
