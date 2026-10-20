local Inbox=require(script.Parent.Transport.Inbox)

local Progress={}

local STAGES={
	image={carregando=0,decodificando=0.06,construindo=0.4,enviando=0.55,persistindo=0.8,finalizando=0.97},
	mesh={carregando=0,analisando=0.05,montando=0.28,construindo=0.42,enviando=0.6,persistindo=0.84,finalizando=0.97},
	media={carregando=0,analisando=0.05,enviando=0.15,processando=0.55,construindo=0.85,persistindo=0.9,finalizando=0.97},
}
local LABELS={
	carregando="Carregando dados",
	decodificando="Decodificando imagem",
	analisando="Lendo arquivo",
	montando="Montando geometria",
	construindo="Construindo no Studio",
	enviando="Enviando para a Roblox",
	processando="Roblox processando o upload",
	persistindo="Gravando payload",
	finalizando="Finalizando",
}
local DEFAULT_RATE={image=3.5,mesh=7,media=2}
local OVERHEAD=0.5
local MIN_SAMPLE=65536
local MIN_SECONDS=0.8
local STALE_SECONDS=20

Progress.STAGES=STAGES
Progress.LABELS=LABELS

local function root()
	return Inbox.root()
end

local function set(fields)
	local folder=root()
	for key,value in pairs(fields) do folder:SetAttribute("P_"..key,value) end
end

function Progress.estimate(kind,bytes)
	local rate=root():GetAttribute("Rate_"..kind) or DEFAULT_RATE[kind] or 5
	return math.max(MIN_SECONDS,OVERHEAD+rate*(math.max(bytes or 0,1)/1048576))
end

function Progress.begin(info)
	local kind="mesh"
	if info.kind=="image" then kind="image" elseif info.kind=="audio" or info.kind=="video" then kind="media" end
	set({
		Active=true,
		Id=tostring(info.id or ""),
		Name=tostring(info.name or "Asset"):sub(1,120),
		Kind=kind,
		Bytes=info.bytes or 0,
		Stage="carregando",
		Fraction=0,
		Started=os.clock(),
		Beat=os.clock(),
		Estimate=Progress.estimate(kind,info.bytes),
		Source=tostring(info.source or "mcp"),
		Finished=0,
	})
end

function Progress.stage(name)
	local folder=root()
	if folder:GetAttribute("P_Active")~=true then return end
	local kind=folder:GetAttribute("P_Kind") or "mesh"
	local fraction=(STAGES[kind] or STAGES.mesh)[name] or folder:GetAttribute("P_Fraction") or 0
	set({Stage=name,Fraction=fraction,Beat=os.clock()})
end

function Progress.batch(index,total)
	set({Index=index or 0,Total=total or 0})
end

function Progress.beat()
	root():SetAttribute("P_Beat",os.clock())
end

function Progress.finish(ok,message)
	local folder=root()
	local started=folder:GetAttribute("P_Started")
	local kind=folder:GetAttribute("P_Kind")
	local bytes=folder:GetAttribute("P_Bytes")
	if ok and started and kind and bytes and bytes>=MIN_SAMPLE then
		local seconds=math.max(0.01,os.clock()-started-OVERHEAD)
		local measured=seconds/(bytes/1048576)
		local previous=folder:GetAttribute("Rate_"..kind)
		local blended=previous and (previous*0.55+measured*0.45) or measured
		folder:SetAttribute("Rate_"..kind,math.clamp(blended,0.05,120))
	end
	set({Active=false,Finished=os.clock(),LastOk=ok==true,LastMessage=tostring(message or ""):sub(1,300),Stage="finalizando",Fraction=1,Beat=os.clock()})
end

function Progress.wrapYield(yield)
	local last=os.clock()
	return function()
		yield()
		local now=os.clock()
		if now-last>=0.25 then
			last=now
			root():SetAttribute("P_Beat",now)
		end
	end
end

function Progress.snapshot()
	local folder=root()
	local out={}
	for key,value in pairs(folder:GetAttributes()) do
		if key:sub(1,2)=="P_" then out[key:sub(3)]=value end
	end
	local now=os.clock()
	local active=out.Active==true
	if active and out.Beat and now-out.Beat>STALE_SECONDS then
		active=false
		out.stale=true
	end
	out.active=active
	if active and out.Started then
		local elapsed=now-out.Started
		local total=out.Estimate or MIN_SECONDS
		local fraction=out.Fraction or 0
		if fraction>=0.25 then
			total=total*0.45+(elapsed/fraction)*0.55
		end
		total=math.max(total,elapsed+MIN_SECONDS)
		out.elapsed=elapsed
		out.remaining=math.max(0.5,total-elapsed)
		out.progress=math.clamp(math.max(fraction,elapsed/total),0,0.98)
		out.label=LABELS[out.Stage] or tostring(out.Stage or "")
	else
		out.progress=active and 0 or 1
	end
	return out
end

return table.freeze(Progress)
