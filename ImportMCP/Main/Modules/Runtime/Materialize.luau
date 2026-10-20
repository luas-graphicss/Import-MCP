local Limits=require(script.Parent.Limits)
local AssetService=game:GetService("AssetService")
local CollectionService=game:GetService("CollectionService")

 
 
 
local Materialize={}

Materialize.MODES={asset=true,session=true}

local MIN_INTERVAL=60/Limits.UPLOADS_PER_MINUTE
local lastUpload=0
local defaultMode="asset"
local availability={state="unknown",message=nil,checkedAt=nil}

local function firstLine(err)
	return tostring(err):match("^[^\n]+") or tostring(err)
end

local function sanitizeName(name)
	local clean=tostring(name or "Asset"):gsub("%.%w+$",""):gsub("[^%w%s_%-]","_"):gsub("%s+"," ")
	clean=clean:match("^%s*(.-)%s*$") or clean
	if #clean==0 then clean="Asset" end
	return clean:sub(1,50)
end

function Materialize.setDefault(mode)
	if mode=="session" or mode=="asset" then defaultMode=mode end
	return defaultMode
end

function Materialize.default()
	return defaultMode
end

 
 
function Materialize.mode(value)
	if value==nil or value=="auto" or value=="default" then return defaultMode end
	if value==false or value=="none" or value=="off" then return false end
	if value==true or value=="session" or value=="runtime" or value=="payload" then return "session" end
	if value=="asset" or value=="permanent" or value=="upload" then return "asset" end
	error("Valor de persist invalido: use 'asset', 'session' ou false.",0)
end

function Materialize.availability()
	return table.clone(availability)
end

local function markAvailability(state,message)
	availability.state=state
	availability.message=message
	availability.checkedAt=os.time()
end

local function throttle(check)
	local remaining=(lastUpload+MIN_INTERVAL)-os.clock()
	while remaining>0 do
		task.wait(math.min(remaining,0.25))
		if check then check() end
		remaining=(lastUpload+MIN_INTERVAL)-os.clock()
	end
	lastUpload=os.clock()
end

local function creatorParams()
	if game.CreatorType==Enum.CreatorType.Group and game.CreatorId>0 then
		return {CreatorId=game.CreatorId,CreatorType=Enum.AssetCreatorType.Group}
	end
	local userId=0
	pcall(function() userId=game:GetService("StudioService"):GetUserId() end)
	if userId==0 and game.CreatorType==Enum.CreatorType.User then userId=game.CreatorId end
	assert(userId>0,"Nao foi possivel identificar o criador (StudioService:GetUserId). Faca login no Studio.")
	return {CreatorId=userId,CreatorType=Enum.AssetCreatorType.User}
end

local function attempt(object,assetType,params)
	local ok,result,payload=pcall(function()
		return AssetService:CreateAssetAsync(object,assetType,params)
	end)
	if not ok then return "unavailable",firstLine(result) end
	if typeof(result)~="EnumItem" then return "unavailable","CreateAssetAsync retornou "..tostring(result) end
	if result.Name=="Success" then
		local id=tonumber(payload)
		if not id then return "failed","Success sem assetId ("..tostring(payload)..")" end
		return "ok",id
	end
	if result.Name=="PermissionDenied" then return "denied",tostring(payload) end
	return "failed",result.Name..": "..tostring(payload)
end

 
 
 
function Materialize.upload(object,assetType,name,options)
	options=options or {}
	local check=options.check
	local params=creatorParams()
	params.Name=sanitizeName(name)
	params.Description=options.description or "Importado pelo ImportMCP"
	local attempts=options.attempts or 3
	local lastKind,lastMessage
	for n=1,attempts do
		throttle(check)
		local kind,payload=attempt(object,assetType,params)
		if check then check() end
		if kind=="ok" then
			markAvailability("available")
			return payload
		end
		lastKind,lastMessage=kind,payload
		if kind=="unavailable" or kind=="denied" then break end
		if n<attempts then task.wait(2*n) end
	end
	if lastKind=="unavailable" or lastKind=="denied" then markAvailability(lastKind,lastMessage) end
	error({code=lastKind,message="Upload de "..tostring(assetType.Name).." '"..params.Name.."' falhou ["..tostring(lastKind).."]: "..tostring(lastMessage)},0)
end

function Materialize.isFallbackError(err)
	return type(err)=="table" and (err.code=="unavailable" or err.code=="denied")
end

function Materialize.errorText(err)
	if type(err)=="table" then return tostring(err.message or err.code) end
	return firstLine(err)
end

 
function Materialize.meshPart(meshId,fidelity,check,timeout)
	local content=Content.fromAssetId(meshId)
	local deadline=os.clock()+(timeout or Limits.ASSET_READY_TIMEOUT)
	local lastError
	repeat
		local ok,part=pcall(AssetService.CreateMeshPartAsync,AssetService,content,fidelity)
		if check then check() end
		if ok and part then
			part:SetAttribute("ImportMCP_MeshId",meshId)
			return part
		end
		lastError=part
		task.wait(2)
	until os.clock()>=deadline
	error("Mesh "..meshId.." enviado mas ainda indisponivel: "..firstLine(lastError),0)
end

 
function Materialize.mark(root,kind,assetIds,info)
	for name in pairs(root:GetAttributes()) do
		if name:sub(1,10)=="ImportMCP_" then root:SetAttribute(name,nil) end
	end
	root:SetAttribute("ImportMCP_Kind",kind)
	root:SetAttribute("ImportMCP_Mode","asset")
	root:SetAttribute("ImportMCP_Version",Limits.VERSION)
	root:SetAttribute("ImportMCP_Status","Asset")
	local ids={}
	for _,id in ipairs(assetIds or {}) do ids[#ids+1]=tostring(id) end
	root:SetAttribute("ImportMCP_AssetIds",table.concat(ids,","):sub(1,Limits.MAX_META))
	root:SetAttribute("ImportMCP_AssetCount",#ids)
	if type(info)=="table" then
		for key,value in pairs(info) do
			if value~=nil and type(value)~="table" then root:SetAttribute("ImportMCP_"..key,value) end
		end
	end
	CollectionService:AddTag(root,Limits.TAG)
end

function Materialize.isPermanent(instance)
	return typeof(instance)=="Instance" and instance:GetAttribute("ImportMCP_Mode")=="asset"
end

function Materialize.assetIds(instance)
	local out={}
	for id in tostring(instance:GetAttribute("ImportMCP_AssetIds") or ""):gmatch("%d+") do out[#out+1]=tonumber(id) end
	return out
end

return table.freeze(Materialize)
