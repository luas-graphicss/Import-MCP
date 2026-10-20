local Inflate={}

local LENGTH_BASE={3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258}
local LENGTH_EXTRA={0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0}
local DISTANCE_BASE={1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577}
local DISTANCE_EXTRA={0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13}
local CODE_ORDER={16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15}
local FAST_BITS=9
local FAST_SIZE=512
local WINDOW=32768
local CHUNK=262144
local MAX_OUTPUT=268435456
local SLICE=0.008
local STEP=1024

local POWER={}
for index=0,33 do POWER[index]=2^index end

local REVERSE={}
for value=0,FAST_SIZE-1 do
 local reversed=0
 local bits=value
 for _=1,FAST_BITS do
  reversed=reversed*2+bits%2
  bits=(bits-bits%2)/2
 end
 REVERSE[value]=reversed
end

local function build(lengths,count)
 local counts=table.create(16,0)
 local maxLength=0
 for index=0,count-1 do
  local length=lengths[index] or 0
  if length<0 or length>15 then error("Comprimento de codigo deflate invalido.",0) end
  if length>0 then
   counts[length]+=1
   if length>maxLength then maxLength=length end
  end
 end
 local fast=table.create(FAST_SIZE,0)
 local codes={fast=fast,counts=counts,symbols={},first=0,index=0,maxLength=maxLength}
 if maxLength==0 then return codes end
 local left=1
 for length=1,15 do
  left=left*2-counts[length]
  if left<0 then error("Tabela de codigos deflate sobrecarregada.",0) end
 end
 local cursor=table.create(16,0)
 local total=0
 for length=1,15 do
  cursor[length]=total
  total+=counts[length]
 end
 local assign=table.create(16,0)
 local code=0
 for length=1,15 do
  assign[length]=code
  code=(code+counts[length])*2
 end
 local symbols=codes.symbols
 for index=0,count-1 do
  local length=lengths[index] or 0
  if length>0 then
   symbols[cursor[length]]=index
   cursor[length]+=1
   local value=assign[length]
   assign[length]=value+1
   if length<=FAST_BITS then
    local reversed=0
    local bits=value
    for _=1,length do
     reversed=reversed*2+bits%2
     bits=(bits-bits%2)/2
    end
    local entry=index*16+length
    local stride=POWER[length]
    for slot=reversed,FAST_SIZE-1,stride do fast[slot]=entry end
   end
  end
 end
 local first=0
 local skip=0
 for length=1,FAST_BITS do
  skip+=counts[length]
  first=(first+counts[length])*2
 end
 codes.first=first
 codes.index=skip
 return codes
end

local function fill(state,amount)
 local acc=state.acc
 local filled=state.filled
 local source=state.src
 local position=state.pos
 local limit=state.limit
 while filled<amount do
  local byte=0
  if position<limit then
   byte=buffer.readu8(source,position)
   position+=1
  else
   state.pad+=1
   if state.pad>8 then error("Fluxo deflate truncado.",0) end
  end
  acc+=byte*POWER[filled]
  filled+=8
 end
 state.acc=acc
 state.filled=filled
 state.pos=position
end

local function take(state,amount)
 if amount==0 then return 0 end
 if state.filled<amount then fill(state,amount) end
 local divisor=POWER[amount]
 local acc=state.acc
 local value=acc%divisor
 state.acc=(acc-value)/divisor
 state.filled-=amount
 return value
end

local function align(state)
 local extra=state.filled%8
 if extra>0 then
  local divisor=POWER[extra]
  local value=state.acc%divisor
  state.acc=(state.acc-value)/divisor
  state.filled-=extra
 end
 local bytes=state.filled/8
 if bytes>0 then
  state.pos-=bytes
  if state.pos<0 then state.pos=0 end
 end
 state.acc=0
 state.filled=0
end

local function decodeSymbol(state,codes)
 if state.filled<FAST_BITS then fill(state,FAST_BITS) end
 local acc=state.acc
 local peeked=acc%FAST_SIZE
 local entry=codes.fast[peeked]
 if entry~=0 then
  local length=entry%16
  local divisor=POWER[length]
  local value=acc%divisor
  state.acc=(acc-value)/divisor
  state.filled-=length
  return (entry-length)/16
 end
 state.acc=(acc-peeked)/FAST_SIZE
 state.filled-=FAST_BITS
 local code=REVERSE[peeked]
 local first=codes.first
 local index=codes.index
 local counts=codes.counts
 local symbols=codes.symbols
 for length=FAST_BITS+1,15 do
  code=code*2+take(state,1)
  local count=counts[length]
  if code-first<count then
   local symbol=symbols[index+code-first]
   if symbol==nil then error("Simbolo deflate ausente.",0) end
   return symbol
  end
  index+=count
  first=(first+count)*2
 end
 error("Codigo deflate invalido.",0)
end

local function tick(state)
 local yield=state.yield
 if not yield then return end
 local now=os.clock()
 if now-state.mark>=SLICE then
  yield()
  state.mark=os.clock()
 end
end

local function flush(state,final)
 local keep=final and 0 or WINDOW
 local upto=state.length-keep
 if upto>state.sent then
  state.sink(state.out,state.sent,upto-state.sent)
  state.sent=upto
 end
 if not final and state.length>keep then
  buffer.copy(state.out,0,state.out,state.length-keep,keep)
  state.length=keep
  state.sent=0
 end
end

local function grow(state,required)
 if required>state.cap then error("Fluxo deflate maior que o declarado.",0) end
 local size=state.capacity
 if size<CHUNK then size=CHUNK end
 while size<required do size*=2 end
 if size>state.cap then size=state.cap end
 local grown=buffer.create(size)
 buffer.copy(grown,0,state.out,0,state.length)
 state.out=grown
 state.capacity=size
end

local function reserve(state,needed)
 if state.length+needed<=state.capacity then return end
 if state.sink then
  flush(state,false)
  if state.length+needed>state.capacity then error("Janela deflate insuficiente.",0) end
 else
  grow(state,state.length+needed)
 end
end

local function stored(state)
 align(state)
 if state.pos+4>state.limit then error("Bloco deflate incompleto.",0) end
 local source=state.src
 local length=buffer.readu8(source,state.pos)+buffer.readu8(source,state.pos+1)*256
 local check=buffer.readu8(source,state.pos+2)+buffer.readu8(source,state.pos+3)*256
 state.pos+=4
 if length+check~=65535 then error("Bloco deflate sem verificacao valida.",0) end
 if state.pos+length>state.limit then error("Bloco deflate fora do arquivo.",0) end
 local remaining=length
 while remaining>0 do
  local piece=remaining
  if piece>CHUNK then piece=CHUNK end
  reserve(state,piece)
  buffer.copy(state.out,state.length,source,state.pos,piece)
  state.length+=piece
  state.produced+=piece
  state.pos+=piece
  remaining-=piece
  tick(state)
 end
end

local function payload(state,literals,distances)
 local counter=0
 local out=state.out
 local position=state.length
 local capacity=state.capacity
 local produced=state.produced
 while true do
  local symbol=decodeSymbol(state,literals)
  if symbol<256 then
   if position>=capacity then
    state.length=position
    state.produced=produced
    reserve(state,1)
    out=state.out
    position=state.length
    capacity=state.capacity
   end
   buffer.writeu8(out,position,symbol)
   position+=1
   produced+=1
  elseif symbol==256 then
   break
  else
   local slot=symbol-256
   if slot<1 or slot>29 then error("Comprimento deflate invalido.",0) end
   local run=LENGTH_BASE[slot]
   local extra=LENGTH_EXTRA[slot]
   if extra>0 then run+=take(state,extra) end
   local code=decodeSymbol(state,distances)+1
   if code<1 or code>30 then error("Distancia deflate invalida.",0) end
   local distance=DISTANCE_BASE[code]
   local more=DISTANCE_EXTRA[code]
   if more>0 then distance+=take(state,more) end
   if distance>position then error("Distancia deflate maior que a saida.",0) end
   if position+run>capacity then
    state.length=position
    state.produced=produced
    reserve(state,run)
    out=state.out
    position=state.length
    capacity=state.capacity
   end
   local target=position
   local origin=position-distance
   if distance>=run then
    buffer.copy(out,target,out,origin,run)
   else
    local remaining=run
    while remaining>0 do
     local piece=distance
     if piece>remaining then piece=remaining end
     buffer.copy(out,target,out,origin,piece)
     target+=piece
     origin+=piece
     remaining-=piece
    end
   end
   position+=run
   produced+=run
  end
  counter+=1
  if counter>=STEP then
   counter=0
   state.length=position
   state.produced=produced
   tick(state)
  end
 end
 state.length=position
 state.produced=produced
end

local FIXED_LITERALS,FIXED_DISTANCES

local function fixed()
 if not FIXED_LITERALS then
  local literals={}
  for index=0,143 do literals[index]=8 end
  for index=144,255 do literals[index]=9 end
  for index=256,279 do literals[index]=7 end
  for index=280,287 do literals[index]=8 end
  FIXED_LITERALS=build(literals,288)
  local distances={}
  for index=0,29 do distances[index]=5 end
  FIXED_DISTANCES=build(distances,30)
 end
 return FIXED_LITERALS,FIXED_DISTANCES
end

local function dynamic(state)
 local literalCount=take(state,5)+257
 local distanceCount=take(state,5)+1
 local codeCount=take(state,4)+4
 if literalCount>286 or distanceCount>30 then error("Cabecalho deflate invalido.",0) end
 local codeLengths={}
 for index=0,18 do codeLengths[index]=0 end
 for index=1,codeCount do codeLengths[CODE_ORDER[index]]=take(state,3) end
 local codeTable=build(codeLengths,19)
 local total=literalCount+distanceCount
 local lengths={}
 local index=0
 while index<total do
  local symbol=decodeSymbol(state,codeTable)
  if symbol<16 then
   lengths[index]=symbol
   index+=1
  elseif symbol==16 then
   if index==0 then error("Repeticao deflate sem base.",0) end
   local previous=lengths[index-1]
   local repeats=3+take(state,2)
   for _=1,repeats do
    if index>=total then break end
    lengths[index]=previous
    index+=1
   end
  elseif symbol==17 then
   local repeats=3+take(state,3)
   for _=1,repeats do
    if index>=total then break end
    lengths[index]=0
    index+=1
   end
  else
   local repeats=11+take(state,7)
   for _=1,repeats do
    if index>=total then break end
    lengths[index]=0
    index+=1
   end
  end
 end
 local literalLengths={}
 for position=0,literalCount-1 do literalLengths[position]=lengths[position] or 0 end
 local distanceLengths={}
 for position=0,distanceCount-1 do distanceLengths[position]=lengths[literalCount+position] or 0 end
 return build(literalLengths,literalCount),build(distanceLengths,distanceCount)
end

local function normalize(source,position,limit)
 local data=source
 if type(data)=="string" then data=buffer.fromstring(data) end
 if typeof(data)~="buffer" then error("Fonte invalida para descompactar.",0) end
 local size=buffer.len(data)
 local from=tonumber(position) or 0
 local to=tonumber(limit) or size
 if from<0 then from=0 end
 if to>size then to=size end
 if from>to then error("Intervalo invalido para descompactar.",0) end
 return data,from,to
end

local function newState(source,position,limit,expected,yield,sink)
 local data,from,to=normalize(source,position,limit)
 local state={src=data,pos=from,limit=to,acc=0,filled=0,pad=0,length=0,sent=0,produced=0,mark=os.clock(),sink=sink}
 if type(yield)=="function" then state.yield=yield end
 if sink then
  state.capacity=WINDOW+CHUNK
  state.cap=MAX_OUTPUT
  state.out=buffer.create(state.capacity)
 else
  local size=tonumber(expected) or 0
  if size~=size or size<0 then size=0 end
  if size>MAX_OUTPUT then error("Bloco compactado acima do limite de memoria.",0) end
  local start=size>0 and size or 65536
  state.capacity=start
  state.cap=size>0 and math.min(MAX_OUTPUT,size+CHUNK) or MAX_OUTPUT
  state.out=buffer.create(start)
 end
 return state
end

local function run(state)
 repeat
  local last=take(state,1)
  local kind=take(state,2)
  if kind==0 then
   stored(state)
  elseif kind==1 then
   local literals,distances=fixed()
   payload(state,literals,distances)
  elseif kind==2 then
   local literals,distances=dynamic(state)
   payload(state,literals,distances)
  else
   error("Bloco deflate reservado.",0)
  end
  tick(state)
 until last==1
 if state.sink then flush(state,true) end
end

local function zlibStart(source,position,limit)
 local data,from,to=normalize(source,position,limit)
 if to-from<2 then error("Fluxo zlib incompleto.",0) end
 local cmf=buffer.readu8(data,from)
 local flg=buffer.readu8(data,from+1)
 if cmf%16~=8 then error("Fluxo zlib com metodo desconhecido.",0) end
 if (cmf*256+flg)%31~=0 then error("Cabecalho zlib invalido.",0) end
 if flg%64>=32 then error("Fluxo zlib com dicionario nao suportado.",0) end
 return data,from+2,to
end

local function looksZlib(source,position,limit)
 local ok,data,from=pcall(zlibStart,source,position,limit)
 return ok and data~=nil and from~=nil
end

function Inflate.raw(source,position,limit,expected,yield)
 local state=newState(source,position,limit,expected,yield,nil)
 run(state)
 return state.out,state.length
end

function Inflate.rawTo(source,position,limit,sink,yield)
 if type(sink)~="function" then error("Destino invalido para descompactar.",0) end
 local state=newState(source,position,limit,nil,yield,sink)
 run(state)
 return state.produced
end

function Inflate.zlib(source,position,limit,expected,yield)
 local data,from,to=zlibStart(source,position,limit)
 return Inflate.raw(data,from,to,expected,yield)
end

function Inflate.zlibTo(source,position,limit,sink,yield)
 local data,from,to=zlibStart(source,position,limit)
 return Inflate.rawTo(data,from,to,sink,yield)
end

function Inflate.auto(source,position,limit,expected,yield)
 if looksZlib(source,position,limit) then
  local ok,out,length=pcall(Inflate.zlib,source,position,limit,expected,yield)
  if ok then return out,length end
  local fine,raw,size=pcall(Inflate.raw,source,position,limit,expected,yield)
  if fine then return raw,size end
  error(out,0)
 end
 local ok,out,length=pcall(Inflate.raw,source,position,limit,expected,yield)
 if ok then return out,length end
 local fine,data,size=pcall(Inflate.zlib,source,position,limit,expected,yield)
 if fine then return data,size end
 error(out,0)
end

function Inflate.autoTo(source,position,limit,sink,yield)
 if looksZlib(source,position,limit) then return Inflate.zlibTo(source,position,limit,sink,yield) end
 return Inflate.rawTo(source,position,limit,sink,yield)
end

Inflate.window=WINDOW

return Inflate
