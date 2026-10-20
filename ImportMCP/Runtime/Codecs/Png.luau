local Inflate=require(script.Parent.Inflate)

local Png={}

local SIGNATURE={137,80,78,71,13,10,26,10}
local CHANNELS={[0]=1,[2]=3,[3]=1,[4]=2,[6]=4}
local DEPTHS={
 [0]={[1]=true,[2]=true,[4]=true,[8]=true,[16]=true},
 [2]={[8]=true,[16]=true},
 [3]={[1]=true,[2]=true,[4]=true,[8]=true},
 [4]={[8]=true,[16]=true},
 [6]={[8]=true,[16]=true},
}
local PASSES={{0,0,8,8},{4,0,8,8},{0,4,4,8},{2,0,4,4},{0,2,2,4},{1,0,2,2},{0,1,1,2}}
local MAX_PIXELS=67108864
local SLICE=0.008

local function u32(source,offset)
 return buffer.readu8(source,offset)*16777216+buffer.readu8(source,offset+1)*65536+buffer.readu8(source,offset+2)*256+buffer.readu8(source,offset+3)
end

local function u16(source,offset)
 return buffer.readu8(source,offset)*256+buffer.readu8(source,offset+1)
end

function Png.matches(source)
 if type(source)=="string" then source=buffer.fromstring(source) end
 if typeof(source)~="buffer" or buffer.len(source)<8 then return false end
 for index=1,8 do
  if buffer.readu8(source,index-1)~=SIGNATURE[index] then return false end
 end
 return true
end

local function paeth(a,b,c)
 local estimate=a+b-c
 local da,db,dc=estimate-a,estimate-b,estimate-c
 if da<0 then da=-da end
 if db<0 then db=-db end
 if dc<0 then dc=-dc end
 if da<=db and da<=dc then return a end
 if db<=dc then return b end
 return c
end

local function header(source,yield)
 local total=buffer.len(source)
 local info,plte,trns
 local segments,compressed={},0
 local offset=8
 while offset+8<=total do
  local length=u32(source,offset)
  local kind=buffer.readstring(source,offset+4,4)
  local start=offset+8
  if start+length>total then error("Arquivo PNG truncado.",0) end
  if kind=="IHDR" then
   if length<13 then error("Cabecalho PNG invalido.",0) end
   info={width=u32(source,start),height=u32(source,start+4),depth=buffer.readu8(source,start+8),color=buffer.readu8(source,start+9),
    compression=buffer.readu8(source,start+10),filter=buffer.readu8(source,start+11),interlace=buffer.readu8(source,start+12)}
  elseif kind=="PLTE" then
   plte={at=start,size=length}
  elseif kind=="tRNS" then
   trns={at=start,size=length}
  elseif kind=="IDAT" then
   segments[#segments+1]={start,length}
   compressed=compressed+length
  elseif kind=="IEND" then
   break
  end
  offset=start+length+4
  if yield then yield() end
 end
 if not info then error("PNG sem cabecalho IHDR.",0) end
 if info.width<1 or info.height<1 then error("Dimensoes de PNG invalidas.",0) end
 if info.width*info.height>MAX_PIXELS then error("Imagem PNG grande demais.",0) end
 if info.compression~=0 or info.filter~=0 then error("Compressao PNG nao suportada.",0) end
 if info.interlace~=0 and info.interlace~=1 then error("Entrelacamento PNG nao suportado.",0) end
 local allowed=DEPTHS[info.color]
 if not allowed or not allowed[info.depth] then error("Formato PNG nao suportado: cor "..tostring(info.color).." com "..tostring(info.depth).." bits.",0) end
 if info.color==3 and not plte then error("PNG indexado sem paleta.",0) end
 if compressed==0 then error("PNG sem dados de imagem.",0) end
 local data=buffer.create(compressed)
 local at=0
 for _,segment in ipairs(segments) do
  buffer.copy(data,at,source,segment[1],segment[2])
  at=at+segment[2]
  if yield then yield() end
 end
 return info,plte,trns,data
end

local function palette(source,plte,trns)
 local count=plte.size//3
 if count<1 then error("Paleta PNG vazia.",0) end
 local reds,greens,blues,alphas={},{},{},{}
 for index=0,count-1 do
  reds[index]=buffer.readu8(source,plte.at+index*3)
  greens[index]=buffer.readu8(source,plte.at+index*3+1)
  blues[index]=buffer.readu8(source,plte.at+index*3+2)
  alphas[index]=255
 end
 if trns then
  local limit=math.min(trns.size,count)
  for index=0,limit-1 do alphas[index]=buffer.readu8(source,trns.at+index) end
 end
 return reds,greens,blues,alphas
end

local function reader(info,source,plte,trns)
 local depth,color=info.depth,info.color
 if color==3 then
  local reds,greens,blues,alphas=palette(source,plte,trns)
  if depth==8 then
   return function(lines,row,x)
    local index=buffer.readu8(lines,row+x)
    local red=reds[index]
    if red==nil then error("Indice fora da paleta PNG.",0) end
    return red,greens[index],blues[index],alphas[index]
   end
  end
  local per=8//depth
  local mask=bit32.lshift(1,depth)-1
  return function(lines,row,x)
   local byte=buffer.readu8(lines,row+x//per)
   local index=bit32.band(bit32.rshift(byte,(per-1-(x%per))*depth),mask)
   local red=reds[index]
   if red==nil then error("Indice fora da paleta PNG.",0) end
   return red,greens[index],blues[index],alphas[index]
  end
 end
 if color==0 then
  local key=(trns and trns.size>=2) and u16(source,trns.at) or nil
  if depth==16 then
   if key==nil then
    return function(lines,row,x)
     local high=buffer.readu8(lines,row+x*2)
     return high,high,high,255
    end
   end
   return function(lines,row,x)
    local at=row+x*2
    local high=buffer.readu8(lines,at)
    local value=high*256+buffer.readu8(lines,at+1)
    return high,high,high,(key==value) and 0 or 255
   end
  end
  if depth==8 then
   return function(lines,row,x)
    local gray=buffer.readu8(lines,row+x)
    return gray,gray,gray,(key==gray) and 0 or 255
   end
  end
  local per=8//depth
  local mask=bit32.lshift(1,depth)-1
  local scale=255/mask
  return function(lines,row,x)
   local byte=buffer.readu8(lines,row+x//per)
   local value=bit32.band(bit32.rshift(byte,(per-1-(x%per))*depth),mask)
   local gray=math.floor(value*scale+0.5)
   return gray,gray,gray,(key==value) and 0 or 255
  end
 end
 if color==2 then
  local keyR,keyG,keyB
  if trns and trns.size>=6 then
   keyR,keyG,keyB=u16(source,trns.at),u16(source,trns.at+2),u16(source,trns.at+4)
  end
  if depth==16 then
   if keyR==nil then
    return function(lines,row,x)
     local at=row+x*6
     return buffer.readu8(lines,at),buffer.readu8(lines,at+2),buffer.readu8(lines,at+4),255
    end
   end
   return function(lines,row,x)
    local at=row+x*6
    local red=buffer.readu8(lines,at)*256+buffer.readu8(lines,at+1)
    local green=buffer.readu8(lines,at+2)*256+buffer.readu8(lines,at+3)
    local blue=buffer.readu8(lines,at+4)*256+buffer.readu8(lines,at+5)
    local alpha=(keyR==red and keyG==green and keyB==blue) and 0 or 255
    return red//256,green//256,blue//256,alpha
   end
  end
  return function(lines,row,x)
   local at=row+x*3
   local red,green,blue=buffer.readu8(lines,at),buffer.readu8(lines,at+1),buffer.readu8(lines,at+2)
   local alpha=(keyR==red and keyG==green and keyB==blue) and 0 or 255
   return red,green,blue,alpha
  end
 end
 if color==6 then
  if depth==16 then
   return function(lines,row,x)
    local at=row+x*8
    return buffer.readu8(lines,at),buffer.readu8(lines,at+2),buffer.readu8(lines,at+4),buffer.readu8(lines,at+6)
   end
  end
  return function(lines,row,x)
   local at=row+x*4
   return buffer.readu8(lines,at),buffer.readu8(lines,at+1),buffer.readu8(lines,at+2),buffer.readu8(lines,at+3)
  end
 end
 if depth==16 then
  return function(lines,row,x)
   local at=row+x*4
   local gray=buffer.readu8(lines,at)
   return gray,gray,gray,buffer.readu8(lines,at+2)
  end
 end
 return function(lines,row,x)
  local at=row+x*2
  local gray=buffer.readu8(lines,at)
  return gray,gray,gray,buffer.readu8(lines,at+1)
 end
end

local readu8=buffer.readu8
local writeu8=buffer.writeu8

local function addBytes(a,b)
 return bit32.bxor(bit32.band(a,0x7F7F7F7F)+bit32.band(b,0x7F7F7F7F),bit32.band(bit32.bxor(a,b),0x80808080))
end

local function subRow(cur,rowBytes,bpp,laneStep)
 laneStep=laneStep or 1
 if bpp==4 and rowBytes>=8 then
  local left=buffer.readu32(cur,0)
  local index=4
  while index+4<=rowBytes do
   left=addBytes(buffer.readu32(cur,index),left)
   buffer.writeu32(cur,index,left)
   index+=4
  end
  for at=index,rowBytes-1 do
   buffer.writeu8(cur,at,(buffer.readu8(cur,at)+buffer.readu8(cur,at-4))%256)
  end
  return
 end
 if bpp==8 and rowBytes>=16 then
  local index=8
  while index+4<=rowBytes do
   buffer.writeu32(cur,index,addBytes(buffer.readu32(cur,index),buffer.readu32(cur,index-8)))
   index+=4
  end
  for at=index,rowBytes-1 do
   buffer.writeu8(cur,at,(buffer.readu8(cur,at)+buffer.readu8(cur,at-8))%256)
  end
  return
 end
 for lane=0,bpp-1,laneStep do
  local left=0
  local index=lane
  while index<rowBytes do
   local value=(readu8(cur,index)+left)%256
   writeu8(cur,index,value)
   left=value
   index+=bpp
  end
 end
end

local function unfilterRow(cur,prev,src,rowBytes,bpp,mode,first,laneStep)
 laneStep=laneStep or 1
 if mode==0 then
  buffer.copy(cur,0,src,1,rowBytes)
 elseif mode==1 then
  buffer.copy(cur,0,src,1,rowBytes)
  subRow(cur,rowBytes,bpp,laneStep)
 elseif mode==2 then
  if first then
   buffer.copy(cur,0,src,1,rowBytes)
  else
   local index=0
   while index+4<=rowBytes do
    buffer.writeu32(cur,index,addBytes(buffer.readu32(src,1+index),buffer.readu32(prev,index)))
    index+=4
   end
   for at=index,rowBytes-1 do
    buffer.writeu8(cur,at,(buffer.readu8(src,1+at)+buffer.readu8(prev,at))%256)
   end
  end
 elseif mode==3 then
  if first then
   for lane=0,bpp-1,laneStep do
    local left=readu8(src,1+lane)
    writeu8(cur,lane,left)
    local index=lane+bpp
    while index<rowBytes do
     local value=(readu8(src,1+index)+left//2)%256
     writeu8(cur,index,value)
     left=value
     index+=bpp
    end
   end
  elseif bpp<=8 then
   for lane=0,bpp-1,laneStep do
    local left=0
    local index=lane
    while index<rowBytes do
     local value=(readu8(src,1+index)+(left+readu8(prev,index))//2)%256
     writeu8(cur,index,value)
     left=value
     index+=bpp
    end
   end
  else
   for index=0,bpp-1 do
    buffer.writeu8(cur,index,(buffer.readu8(src,1+index)+buffer.readu8(prev,index)//2)%256)
   end
   for index=bpp,rowBytes-1 do
    buffer.writeu8(cur,index,(buffer.readu8(src,1+index)+(buffer.readu8(cur,index-bpp)+buffer.readu8(prev,index))//2)%256)
   end
  end
 elseif mode==4 then
  if first then
   buffer.copy(cur,0,src,1,rowBytes)
   subRow(cur,rowBytes,bpp,laneStep)
  elseif bpp<=8 then
   for lane=0,bpp-1,laneStep do
    local left=0
    local upLeft=0
    local index=lane
    while index<rowBytes do
     local up=readu8(prev,index)
     local estimate=left+up-upLeft
     local da=estimate-left
     local db=estimate-up
     local dc=estimate-upLeft
     if da<0 then da=-da end
     if db<0 then db=-db end
     if dc<0 then dc=-dc end
     local predictor
     if da<=db and da<=dc then predictor=left elseif db<=dc then predictor=up else predictor=upLeft end
     local value=(readu8(src,1+index)+predictor)%256
     writeu8(cur,index,value)
     left=value
     upLeft=up
     index+=bpp
    end
   end
  else
   for index=0,bpp-1 do
    buffer.writeu8(cur,index,(buffer.readu8(src,1+index)+buffer.readu8(prev,index))%256)
   end
   for index=bpp,rowBytes-1 do
    buffer.writeu8(cur,index,(buffer.readu8(src,1+index)+paeth(buffer.readu8(cur,index-bpp),buffer.readu8(prev,index),buffer.readu8(prev,index-bpp)))%256)
   end
  end
 else
  error("Filtro PNG desconhecido: "..tostring(mode),0)
 end
end

function Png.probe(source)
 if type(source)=="string" then source=buffer.fromstring(source) end
 if not Png.matches(source) then return nil end
 local total=buffer.len(source)
 if total<33 then return nil end
 local length=u32(source,8)
 if buffer.readstring(source,12,4)~="IHDR" or length<13 then return nil end
 local width=u32(source,16)
 local height=u32(source,20)
 local depth=buffer.readu8(source,24)
 local color=buffer.readu8(source,25)
 local interlace=buffer.readu8(source,28)
 local channels=CHANNELS[color]
 if not channels or width<1 or height<1 then return nil end
 local rowBytes=(width*channels*depth+7)//8
 return {width=width,height=height,depth=depth,color=color,interlace=interlace,raw=height*(rowBytes+1)}
end

function Png.decode(source,options)
 options=options or {}
 local yield=options.yield
 if type(source)=="string" then source=buffer.fromstring(source) end
 if not Png.matches(source) then error("Arquivo PNG invalido.",0) end
 local info,plte,trns,data=header(source,yield)
 local width,height,depth,color=info.width,info.height,info.depth,info.color
 local channels=CHANNELS[color]
 local bpp=math.max(1,(channels*depth+7)//8)
 local limit=math.floor(tonumber(options.maxSize) or 0)
 local step=1
 if limit>=8 then
  local wide=math.ceil(width/limit)
  local tall=math.ceil(height/limit)
  step=math.max(wide,tall,1)
 end
 local outWidth=math.max(1,math.ceil(width/step))
 local outHeight=math.max(1,math.ceil(height/step))
 local out=buffer.create(outWidth*outHeight*4)
 local read=reader(info,source,plte,trns)
 local direct=(depth==8 and color==6)
 local laneStep=1
 if depth==16 and not ((color==0 or color==2) and trns) then laneStep=2 end
 local layout={}
 if info.interlace==0 then
  layout[1]={rowBytes=(width*channels*depth+7)//8,cols=width,rows=height,x0=0,y0=0,dx=1,dy=1}
 else
  for _,pass in ipairs(PASSES) do
   local cols=(width-pass[1]+pass[3]-1)//pass[3]
   local rows=(height-pass[2]+pass[4]-1)//pass[4]
   if cols>0 and rows>0 then
    layout[#layout+1]={rowBytes=(cols*channels*depth+7)//8,cols=cols,rows=rows,x0=pass[1],y0=pass[2],dx=pass[3],dy=pass[4]}
   end
  end
 end
 local picks={0}
 if step==2 then
  picks={0,1}
 elseif step>2 then
  local shift=(step-1)//3
  local other=step-1-shift
  if other<shift then other=shift end
  picks={shift,other}
 end
 local pickCount=#picks
 local pickRow={}
 for _,offset in ipairs(picks) do pickRow[offset]=true end
 local sums=nil
 if step>1 and info.interlace==0 then sums=buffer.create(outWidth*20) end
 local currentGroup=-1
 local mark=os.clock()
 local function pace()
  if not yield then return end
  local now=os.clock()
  if now-mark>=SLICE then
   yield()
   mark=os.clock()
  end
 end
 local function flushGroup()
  if currentGroup<0 or not sums then return end
  local base=currentGroup*outWidth*4
  for ox=0,outWidth-1 do
   local at=ox*20
   local count=buffer.readu32(sums,at+16)
   if count>0 then
    local half=count//2
    local target=base+ox*4
    buffer.writeu8(out,target,(buffer.readu32(sums,at)+half)//count)
    buffer.writeu8(out,target+1,(buffer.readu32(sums,at+4)+half)//count)
    buffer.writeu8(out,target+2,(buffer.readu32(sums,at+8)+half)//count)
    buffer.writeu8(out,target+3,(buffer.readu32(sums,at+12)+half)//count)
   end
  end
  buffer.fill(sums,0,0)
  currentGroup=-1
 end
 local function emitFull(line,y)
  local base=y*outWidth*4
  if direct then
   buffer.copy(out,base,line,0,width*4)
  else
   for x=0,width-1 do
    local red,green,blue,alpha=read(line,0,x)
    local at=base+x*4
    buffer.writeu8(out,at,red)
    buffer.writeu8(out,at+1,green)
    buffer.writeu8(out,at+2,blue)
    buffer.writeu8(out,at+3,alpha)
   end
  end
 end
 local function emitScaled(line,y)
  local group=y//step
  if group~=currentGroup then
   flushGroup()
   currentGroup=group
  end
  if not pickRow[y%step] then return end
  for ox=0,outWidth-1 do
   local baseX=ox*step
   local at=ox*20
   local red=buffer.readu32(sums,at)
   local green=buffer.readu32(sums,at+4)
   local blue=buffer.readu32(sums,at+8)
   local alpha=buffer.readu32(sums,at+12)
   local count=buffer.readu32(sums,at+16)
   for index=1,pickCount do
    local x=baseX+picks[index]
    if x<width then
     local sr,sg,sb,sa=read(line,0,x)
     red+=sr
     green+=sg
     blue+=sb
     alpha+=sa
     count+=1
    end
   end
   buffer.writeu32(sums,at,red)
   buffer.writeu32(sums,at+4,green)
   buffer.writeu32(sums,at+8,blue)
   buffer.writeu32(sums,at+12,alpha)
   buffer.writeu32(sums,at+16,count)
  end
 end
 local function emitPass(pass,line,rowInPass)
  if info.interlace==0 then
   if step==1 then
    emitFull(line,rowInPass)
   else
    emitScaled(line,rowInPass)
   end
   return
  end
  local y=pass.y0+rowInPass*pass.dy
  if y%step~=0 then return end
  local oy=y//step
  if oy>=outHeight then return end
  local base=oy*outWidth*4
  for column=0,pass.cols-1 do
   local x=pass.x0+column*pass.dx
   if x%step==0 then
    local ox=x//step
    if ox<outWidth then
     local red,green,blue,alpha=read(line,0,column)
     local at=base+ox*4
     buffer.writeu8(out,at,red)
     buffer.writeu8(out,at+1,green)
     buffer.writeu8(out,at+2,blue)
     buffer.writeu8(out,at+3,alpha)
    end
   end
  end
 end
 local passIndex=1
 local current=layout[1]
 if not current then error("PNG sem linhas para decodificar.",0) end
 local rowBytes=current.rowBytes
 local widest=rowBytes
 for _,pass in ipairs(layout) do
  if pass.rowBytes>widest then widest=pass.rowBytes end
 end
 local pending=buffer.create(widest+1)
 local cur=buffer.create(widest)
 local prev=buffer.create(widest)
 local rowInPass=0
 local have=0
 local need=rowBytes+1
 local done=false
 local function handleRow()
  local mode=buffer.readu8(pending,0)
  unfilterRow(cur,prev,pending,rowBytes,bpp,mode,rowInPass==0,laneStep)
  emitPass(current,cur,rowInPass)
  local swap=prev
  prev=cur
  cur=swap
  rowInPass+=1
  if rowInPass>=current.rows then
   passIndex+=1
   current=layout[passIndex]
   if not current then
    done=true
   else
    rowBytes=current.rowBytes
    need=rowBytes+1
    rowInPass=0
    buffer.fill(prev,0,0)
   end
  end
  pace()
 end
 local function sink(chunk,offset,count)
  while count>0 do
   if done then return end
   local wanted=need-have
   local piece=count
   if piece>wanted then piece=wanted end
   buffer.copy(pending,have,chunk,offset,piece)
   have+=piece
   offset+=piece
   count-=piece
   if have==need then
    have=0
    handleRow()
   end
  end
 end
 Inflate.zlibTo(data,0,buffer.len(data),sink,yield)
 flushGroup()
 if not done then error("Dados PNG incompletos.",0) end
 return {width=outWidth,height=outHeight,pixels=out,format="png",hasAlpha=(color==4 or color==6 or trns~=nil),
  sourceWidth=width,sourceHeight=height,resized=step>1,depth=depth,step=step}
end

return Png
