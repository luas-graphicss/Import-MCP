local Runtime=script.Parent.Parent.Runtime
local Limits=require(Runtime.Limits)
local Base64=require(Runtime.Base64)
local ServerStorage=game:GetService("ServerStorage")
local HttpService=game:GetService("HttpService")

local Inbox={}

local STATES={uploading=true,ready=true,queued=true,running=true,done=true,failed=true}

function Inbox.root()
	local home=ServerStorage:FindFirstChild("ImportMCP")
	if not home then
		home=Instance.new("Folder")
		home.Name="ImportMCP"
		home.Parent=ServerStorage
	end
	local inbox=home:FindFirstChild(Limits.INBOX)
	if not inbox then
		inbox=Instance.new("Folder")
		inbox.Name=Limits.INBOX
		inbox.Parent=home
	end
	return inbox
end

local function sanitize(id)
	id=tostring(id or "")
	id=id:gsub("[^%w%-_%.]","_")
	assert(#id>0 and #id<=64,"Id de upload invalido.")
	return id
end

function Inbox.find(id)
	return Inbox.root():FindFirstChild(sanitize(id))
end

function Inbox.get(id)
	local job=Inbox.find(id)
	assert(job,"Upload '"..tostring(id).."' nao existe no Inbox.")
	return job
end

function Inbox.newId(prefix)
	return (prefix or "up").."_"..HttpService:GenerateGUID(false):sub(1,8):lower()
end

function Inbox.begin(id,meta)
	meta=meta or {}
	id=id and sanitize(id) or Inbox.newId("up")
	local existing=Inbox.find(id)
	if existing then existing:Destroy() end
	local job=Instance.new("Folder")
	job.Name=id
	job:SetAttribute("State","uploading")
	job:SetAttribute("Encoding",meta.encoding=="text" and "text" or "base64")
	job:SetAttribute("FileName",tostring(meta.name or meta.fileName or id):sub(1,120))
	job:SetAttribute("Chunks",0)
	job:SetAttribute("Chars",0)
	job:SetAttribute("Created",os.time())
	job:SetAttribute("Order",os.clock())
	if meta.expectedBytes then job:SetAttribute("ExpectedBytes",math.floor(tonumber(meta.expectedBytes) or 0)) end
	local data=Instance.new("Folder")
	data.Name="Data"
	data.Parent=job
	job.Parent=Inbox.root()
	return id
end

function Inbox.append(id,text)
	assert(type(text)=="string" and #text>0,"Chunk vazio.")
	local job=Inbox.get(id)
	assert(job:GetAttribute("State")=="uploading","Upload '"..id.."' ja foi finalizado.")
	local data=job:FindFirstChild("Data")
	local count=job:GetAttribute("Chunks") or 0
	local chars=job:GetAttribute("Chars") or 0
	local maxChars=math.ceil(Limits.MAX_BYTES/3)*4
	assert(chars+#text<=maxChars,"Upload excede "..(Limits.MAX_BYTES//1048576).." MiB.")
	local cursor=1
	while cursor<=#text do
		count+=1
		local chunk=Instance.new("StringValue")
		chunk.Name=string.format("Data_%05d",count)
		chunk.Value=text:sub(cursor,cursor+Limits.STORE_CHUNK-1)
		chunk.Parent=data
		cursor+=Limits.STORE_CHUNK
	end
	chars+=#text
	job:SetAttribute("Chunks",count)
	job:SetAttribute("Chars",chars)
	return {id=id,chunks=count,chars=chars}
end

function Inbox.finish(id)
	local job=Inbox.get(id)
	assert((job:GetAttribute("Chunks") or 0)>0,"Upload '"..id.."' sem dados.")
	job:SetAttribute("State","ready")
	return Inbox.describe(job)
end

function Inbox.text(id,yield)
	local job=Inbox.get(id)
	local data=job:FindFirstChild("Data")
	local count=job:GetAttribute("Chunks") or 0
	local pieces=table.create(count)
	for index=1,count do
		local chunk=data:FindFirstChild(string.format("Data_%05d",index))
		assert(chunk,"Chunk "..index.." ausente no upload '"..id.."'.")
		pieces[index]=chunk.Value
		if yield and index%32==0 then yield() end
	end
	return table.concat(pieces)
end

function Inbox.bytes(id,yield)
	local job=Inbox.get(id)
	local state=job:GetAttribute("State")
	assert(state~="uploading","Upload '"..id.."' ainda nao foi finalizado; chame finish.")
	local text=Inbox.text(id,yield)
	if job:GetAttribute("Encoding")=="text" then return buffer.fromstring(text) end
	local bytes=Base64.decode(text,yield,Limits.MAX_BYTES)
	local expected=job:GetAttribute("ExpectedBytes")
	if expected and expected>0 then assert(buffer.len(bytes)==expected,"Upload '"..id.."' tem "..buffer.len(bytes).." bytes, esperado "..expected..".") end
	return bytes
end

function Inbox.setState(id,state,fields)
	assert(STATES[state],"Estado invalido.")
	local job=Inbox.get(id)
	job:SetAttribute("State",state)
	if fields then
		for key,value in pairs(fields) do
			if type(value)=="table" then value=HttpService:JSONEncode(value) end
			job:SetAttribute(key,value)
		end
	end
	return job
end

function Inbox.describe(job)
	if type(job)=="string" then job=Inbox.get(job) end
	local out={id=job.Name}
	for key,value in pairs(job:GetAttributes()) do out[key]=value end
	return out
end

function Inbox.list(state)
	local out={}
	for _,job in ipairs(Inbox.root():GetChildren()) do
		if job:IsA("Folder") and (state==nil or job:GetAttribute("State")==state) then out[#out+1]=Inbox.describe(job) end
	end
	table.sort(out,function(a,b)
		if (a.Created or 0)~=(b.Created or 0) then return (a.Created or 0)<(b.Created or 0) end
		return (a.Order or 0)<(b.Order or 0)
	end)
	return out
end

function Inbox.remove(id)
	local job=Inbox.find(id)
	if job then job:Destroy() return true end
	return false
end

function Inbox.clear(keepUnfinished)
	local removed=0
	for _,job in ipairs(Inbox.root():GetChildren()) do
		local state=job:GetAttribute("State")
		if not keepUnfinished or state=="done" or state=="failed" then
			job:Destroy()
			removed+=1
		end
	end
	return removed
end

return table.freeze(Inbox)
