local Jpeg={}

local MAX_PIXELS=33554432
local ZIGZAG={0,1,8,16,9,2,3,10,17,24,32,25,18,11,4,5,12,19,26,33,40,48,41,34,27,20,13,6,7,14,21,28,35,42,49,56,57,50,43,36,29,22,15,23,30,37,44,51,58,59,52,45,38,31,39,46,53,60,61,54,47,55,62,63}
local COS1,SIN1=4017,799
local COS3,SIN3=3406,2276
local COS6,SIN6=1567,3784
local SQRT2,SQRT1D2=5793,2896

local function u16(source,offset)
	return buffer.readu8(source,offset)*256+buffer.readu8(source,offset+1)
end

local function clamp8(value)
	if value<=0 then return 0 end
	if value>=255 then return 255 end
	return math.floor(value+0.5)
end

local function pack8(value)
	if value<16 then return 0 end
	if value>=4080 then return 255 end
	return value//16
end

function Jpeg.matches(source)
	if type(source)=="string" then source=buffer.fromstring(source) end
	if typeof(source)~="buffer" or buffer.len(source)<4 then return false end
	return buffer.readu8(source,0)==255 and buffer.readu8(source,1)==216 and buffer.readu8(source,2)==255
end

local function huffmanTable(counts,values)
	local mincode=table.create(16,0)
	local maxcode=table.create(16,-1)
	local valptr=table.create(16,1)
	local code=0
	local index=1
	for length=1,16 do
		valptr[length]=index
		mincode[length]=code
		local count=counts[length]
		if count>0 then
			code+=count
			index+=count
			maxcode[length]=code-1
		else
			maxcode[length]=-1
		end
		code*=2
	end
	return {mincode=mincode,maxcode=maxcode,valptr=valptr,values=values}
end

local function findMarker(source,offset,total)
	local at=offset
	while at+1<total do
		if buffer.readu8(source,at)==255 then
			local following=buffer.readu8(source,at+1)
			if following~=0 and following~=255 then return 65280+following,at end
		end
		at+=1
	end
	return nil,total
end

local function prepareComponents(frame)
	local mcusPerLine=math.ceil(frame.samplesPerLine/8/frame.maxH)
	local mcusPerColumn=math.ceil(frame.scanLines/8/frame.maxV)
	for _,component in ipairs(frame.components) do
		local blocksPerLine=math.ceil(math.ceil(frame.samplesPerLine/8)*component.h/frame.maxH)
		local blocksPerColumn=math.ceil(math.ceil(frame.scanLines/8)*component.v/frame.maxV)
		local blocksPerLineForMcu=mcusPerLine*component.h
		local blocksPerColumnForMcu=mcusPerColumn*component.v
		component.blocksPerLine=blocksPerLine
		component.blocksPerColumn=blocksPerColumn
		component.stride=64*(blocksPerLine+1)
		component.blockData=buffer.create(128*blocksPerColumnForMcu*(blocksPerLineForMcu+1))
		component.pred=0
	end
	frame.mcusPerLine=mcusPerLine
	frame.mcusPerColumn=mcusPerColumn
end

local function decodeScan(source,total,offset,frame,components,resetInterval,spectralStart,spectralEnd,successivePrev,successive,yield)
	local mcusPerLine=frame.mcusPerLine
	local progressive=frame.progressive
	local startOffset=offset
	local componentCount=#components
	local shift=bit32.lshift(1,successive)
	local bitsData=0
	local bitsCount=0
	local ended=false
	local eobrun=0
	local acState=0
	local acNext=0

	for index=1,componentCount do
		local component=components[index]
		if spectralStart==0 and not component.tableDC then error("Tabela Huffman DC ausente no JPEG.",0) end
		if spectralEnd>0 and not component.tableAC then error("Tabela Huffman AC ausente no JPEG.",0) end
	end

	local function readBit()
		if bitsCount>0 then
			bitsCount-=1
			return bit32.band(bit32.rshift(bitsData,bitsCount),1)
		end
		if ended or offset>=total then return 0 end
		local byte=buffer.readu8(source,offset)
		offset+=1
		if byte==255 then
			local following=offset<total and buffer.readu8(source,offset) or 217
			if following==0 then
				offset+=1
			else
				offset-=1
				ended=true
				return 0
			end
		end
		bitsData=byte
		bitsCount=7
		return bit32.rshift(byte,7)
	end

	local function decodeHuffman(tbl)
		local maxcode=tbl.maxcode
		local code=readBit()
		for length=1,16 do
			local limit=maxcode[length]
			if limit>=0 and code<=limit then
				local value=tbl.values[tbl.valptr[length]+code-tbl.mincode[length]]
				if not value then error("Tabela Huffman incompleta no JPEG.",0) end
				return value
			end
			code=code*2+readBit()
		end
		error("Codigo Huffman invalido no JPEG.",0)
	end

	local function receive(length)
		local value=0
		for _=1,length do value=value*2+readBit() end
		return value
	end

	local function receiveAndExtend(length)
		if length==1 then return readBit()==1 and 1 or -1 end
		local value=receive(length)
		if value<bit32.lshift(1,length-1) then return value-bit32.lshift(1,length)+1 end
		return value
	end

	local function decodeBaseline(component,blockOffset)
		local blockData=component.blockData
		local size=decodeHuffman(component.tableDC)
		local diff=size==0 and 0 or receiveAndExtend(size)
		component.pred+=diff
		buffer.writei16(blockData,blockOffset*2,component.pred)
		local k=1
		while k<64 do
			local rs=decodeHuffman(component.tableAC)
			local magnitude=bit32.band(rs,15)
			local run=bit32.rshift(rs,4)
			if magnitude==0 then
				if run<15 then break end
				k+=16
			else
				k+=run
				if k>63 then break end
				buffer.writei16(blockData,(blockOffset+ZIGZAG[k+1])*2,receiveAndExtend(magnitude))
				k+=1
			end
		end
	end

	local function decodeDCFirst(component,blockOffset)
		local size=decodeHuffman(component.tableDC)
		local diff=size==0 and 0 or receiveAndExtend(size)*shift
		component.pred+=diff
		buffer.writei16(component.blockData,blockOffset*2,component.pred)
	end

	local function decodeDCSuccessive(component,blockOffset)
		local at=blockOffset*2
		local raw=buffer.readu16(component.blockData,at)
		buffer.writeu16(component.blockData,at,bit32.band(bit32.bor(raw,bit32.lshift(readBit(),successive)),65535))
	end

	local function decodeACFirst(component,blockOffset)
		if eobrun>0 then
			eobrun-=1
			return
		end
		local k=spectralStart
		while k<=spectralEnd do
			local rs=decodeHuffman(component.tableAC)
			local magnitude=bit32.band(rs,15)
			local run=bit32.rshift(rs,4)
			if magnitude==0 then
				if run<15 then
					eobrun=receive(run)+bit32.lshift(1,run)-1
					break
				end
				k+=16
			else
				k+=run
				if k>63 then break end
				buffer.writei16(component.blockData,(blockOffset+ZIGZAG[k+1])*2,receiveAndExtend(magnitude)*shift)
				k+=1
			end
		end
	end

	local function decodeACSuccessive(component,blockOffset)
		local blockData=component.blockData
		local k=spectralStart
		local run=0
		while k<=spectralEnd do
			local at=(blockOffset+ZIGZAG[k+1])*2
			local current=buffer.readi16(blockData,at)
			local sign=current<0 and -1 or 1
			if acState==0 then
				local rs=decodeHuffman(component.tableAC)
				local magnitude=bit32.band(rs,15)
				run=bit32.rshift(rs,4)
				if magnitude==0 then
					if run<15 then
						eobrun=receive(run)+bit32.lshift(1,run)
						acState=4
					else
						run=16
						acState=1
					end
				else
					if magnitude~=1 then error("Codificacao AC progressiva invalida no JPEG.",0) end
					acNext=receiveAndExtend(magnitude)
					acState=run>0 and 2 or 3
				end
			elseif acState==1 or acState==2 then
				if current~=0 then
					buffer.writei16(blockData,at,current+sign*bit32.lshift(readBit(),successive))
				else
					run-=1
					if run==0 then acState=acState==2 and 3 or 0 end
				end
				k+=1
			elseif acState==3 then
				if current~=0 then
					buffer.writei16(blockData,at,current+sign*bit32.lshift(readBit(),successive))
				else
					buffer.writei16(blockData,at,acNext*shift)
					acState=0
				end
				k+=1
			else
				if current~=0 then
					buffer.writei16(blockData,at,current+sign*bit32.lshift(readBit(),successive))
				end
				k+=1
			end
		end
		if acState==4 then
			eobrun-=1
			if eobrun==0 then acState=0 end
		end
	end

	local decodeFn
	if progressive then
		if spectralStart==0 then
			decodeFn=successivePrev==0 and decodeDCFirst or decodeDCSuccessive
		else
			decodeFn=successivePrev==0 and decodeACFirst or decodeACSuccessive
		end
	else
		decodeFn=decodeBaseline
	end

	local mcuExpected
	if componentCount==1 then
		mcuExpected=components[1].blocksPerLine*components[1].blocksPerColumn
	else
		mcuExpected=mcusPerLine*frame.mcusPerColumn
	end
	if resetInterval==0 then resetInterval=mcuExpected end

	local mcu=0
	local sinceYield=0
	while mcu<mcuExpected do
		for index=1,componentCount do components[index].pred=0 end
		eobrun=0
		acState=0
		local count=math.min(resetInterval,mcuExpected-mcu)
		if componentCount==1 then
			local component=components[1]
			local stride=component.blocksPerLine+1
			local perLine=component.blocksPerLine
			for _=1,count do
				decodeFn(component,64*(stride*(mcu//perLine)+mcu%perLine))
				mcu+=1
				sinceYield+=1
				if yield and sinceYield>=128 then
					sinceYield=0
					yield()
				end
			end
		else
			for _=1,count do
				local mcuRow=mcu//mcusPerLine
				local mcuCol=mcu%mcusPerLine
				for index=1,componentCount do
					local component=components[index]
					local stride=component.blocksPerLine+1
					local columns=component.h
					for row=0,component.v-1 do
						local blockRow=mcuRow*component.v+row
						for column=0,columns-1 do
							decodeFn(component,64*(stride*blockRow+mcuCol*columns+column))
						end
					end
				end
				mcu+=1
				sinceYield+=1
				if yield and sinceYield>=64 then
					sinceYield=0
					yield()
				end
			end
		end
		bitsCount=0
		ended=false
		local marker,position=findMarker(source,offset,total)
		if not marker then
			offset=total
			break
		end
		offset=position
		if marker>=65488 and marker<=65495 then
			offset+=2
		else
			break
		end
	end
	return offset-startOffset
end

local function quantizeAndInverse(blockData,offset,scratch,quant)
	for row=0,56,8 do
		local base=(offset+row)*2
		local p0=buffer.readi16(blockData,base)
		local p1=buffer.readi16(blockData,base+2)
		local p2=buffer.readi16(blockData,base+4)
		local p3=buffer.readi16(blockData,base+6)
		local p4=buffer.readi16(blockData,base+8)
		local p5=buffer.readi16(blockData,base+10)
		local p6=buffer.readi16(blockData,base+12)
		local p7=buffer.readi16(blockData,base+14)
		p0*=buffer.readu16(quant,row*2)
		if p1==0 and p2==0 and p3==0 and p4==0 and p5==0 and p6==0 and p7==0 then
			local flat=(SQRT2*p0+512)//1024
			for index=0,7 do buffer.writei32(scratch,(row+index)*4,flat) end
		else
			p1*=buffer.readu16(quant,(row+1)*2)
			p2*=buffer.readu16(quant,(row+2)*2)
			p3*=buffer.readu16(quant,(row+3)*2)
			p4*=buffer.readu16(quant,(row+4)*2)
			p5*=buffer.readu16(quant,(row+5)*2)
			p6*=buffer.readu16(quant,(row+6)*2)
			p7*=buffer.readu16(quant,(row+7)*2)
			local v0=(SQRT2*p0+128)//256
			local v1=(SQRT2*p4+128)//256
			local v2=p2
			local v3=p6
			local v4=(SQRT1D2*(p1-p7)+128)//256
			local v7=(SQRT1D2*(p1+p7)+128)//256
			local v5=p3*16
			local v6=p5*16
			v0=(v0+v1+1)//2
			v1=v0-v1
			local temp=(v2*SIN6+v3*COS6+128)//256
			v2=(v2*COS6-v3*SIN6+128)//256
			v3=temp
			v4=(v4+v6+1)//2
			v6=v4-v6
			v7=(v7+v5+1)//2
			v5=v7-v5
			v0=(v0+v3+1)//2
			v3=v0-v3
			v1=(v1+v2+1)//2
			v2=v1-v2
			temp=(v4*SIN3+v7*COS3+2048)//4096
			v4=(v4*COS3-v7*SIN3+2048)//4096
			v7=temp
			temp=(v5*SIN1+v6*COS1+2048)//4096
			v5=(v5*COS1-v6*SIN1+2048)//4096
			v6=temp
			buffer.writei32(scratch,row*4,v0+v7)
			buffer.writei32(scratch,(row+7)*4,v0-v7)
			buffer.writei32(scratch,(row+1)*4,v1+v6)
			buffer.writei32(scratch,(row+6)*4,v1-v6)
			buffer.writei32(scratch,(row+2)*4,v2+v5)
			buffer.writei32(scratch,(row+5)*4,v2-v5)
			buffer.writei32(scratch,(row+3)*4,v3+v4)
			buffer.writei32(scratch,(row+4)*4,v3-v4)
		end
	end
	for column=0,7 do
		local p0=buffer.readi32(scratch,column*4)
		local p1=buffer.readi32(scratch,(column+8)*4)
		local p2=buffer.readi32(scratch,(column+16)*4)
		local p3=buffer.readi32(scratch,(column+24)*4)
		local p4=buffer.readi32(scratch,(column+32)*4)
		local p5=buffer.readi32(scratch,(column+40)*4)
		local p6=buffer.readi32(scratch,(column+48)*4)
		local p7=buffer.readi32(scratch,(column+56)*4)
		if p1==0 and p2==0 and p3==0 and p4==0 and p5==0 and p6==0 and p7==0 then
			local flat=(SQRT2*p0+8192)//16384
			if flat<-2040 then
				flat=0
			elseif flat>=2024 then
				flat=255
			else
				flat=(flat+2056)//16
			end
			for index=0,7 do buffer.writei16(blockData,(offset+column+index*8)*2,flat) end
		else
			local v0=(SQRT2*p0+2048)//4096
			local v1=(SQRT2*p4+2048)//4096
			local v2=p2
			local v3=p6
			local v4=(SQRT1D2*(p1-p7)+2048)//4096
			local v7=(SQRT1D2*(p1+p7)+2048)//4096
			local v5=p3
			local v6=p5
			v0=(v0+v1+1)//2+4112
			v1=v0-v1
			local temp=(v2*SIN6+v3*COS6+2048)//4096
			v2=(v2*COS6-v3*SIN6+2048)//4096
			v3=temp
			v4=(v4+v6+1)//2
			v6=v4-v6
			v7=(v7+v5+1)//2
			v5=v7-v5
			v0=(v0+v3+1)//2
			v3=v0-v3
			v1=(v1+v2+1)//2
			v2=v1-v2
			temp=(v4*SIN3+v7*COS3+2048)//4096
			v4=(v4*COS3-v7*SIN3+2048)//4096
			v7=temp
			temp=(v5*SIN1+v6*COS1+2048)//4096
			v5=(v5*COS1-v6*SIN1+2048)//4096
			v6=temp
			buffer.writei16(blockData,(offset+column)*2,pack8(v0+v7))
			buffer.writei16(blockData,(offset+column+56)*2,pack8(v0-v7))
			buffer.writei16(blockData,(offset+column+8)*2,pack8(v1+v6))
			buffer.writei16(blockData,(offset+column+48)*2,pack8(v1-v6))
			buffer.writei16(blockData,(offset+column+16)*2,pack8(v2+v5))
			buffer.writei16(blockData,(offset+column+40)*2,pack8(v2-v5))
			buffer.writei16(blockData,(offset+column+24)*2,pack8(v3+v4))
			buffer.writei16(blockData,(offset+column+32)*2,pack8(v3-v4))
		end
	end
end

local function buildComponentData(component,scratch,yield)
	local blockData=component.blockData
	local quant=component.quant
	local stride=component.blocksPerLine+1
	for blockRow=0,component.blocksPerColumn-1 do
		for blockColumn=0,component.blocksPerLine-1 do
			quantizeAndInverse(blockData,64*(stride*blockRow+blockColumn),scratch,quant)
		end
		if yield then yield() end
	end
end

local function plane(frame,component,outWidth,outHeight)
	local columnScale=component.h/frame.maxH*(frame.samplesPerLine/outWidth)
	local rowScale=component.v/frame.maxV*(frame.scanLines/outHeight)
	local maxColumn=component.blocksPerLine*8-1
	local maxRow=component.blocksPerColumn*8-1
	local columns=table.create(outWidth)
	for x=0,outWidth-1 do
		local sample=math.floor(x*columnScale)
		if sample>maxColumn then sample=maxColumn end
		columns[x+1]=(sample//8)*64+sample%8
	end
	return {data=component.blockData,stride=64*(component.blocksPerLine+1),rowScale=rowScale,maxRow=maxRow,columns=columns}
end

local function rowBase(source,y)
	local sample=math.floor(y*source.rowScale)
	if sample>source.maxRow then sample=source.maxRow end
	return source.stride*(sample//8)+(sample%8)*8
end

local function linearize(frame,adobe,outWidth,outHeight,yield)
	local components=frame.components
	local count=#components
	local out=buffer.create(outWidth*outHeight*4)
	local planes=table.create(count)
	for index=1,count do planes[index]=plane(frame,components[index],outWidth,outHeight) end
	if count==1 then
		local gray=planes[1]
		for y=0,outHeight-1 do
			local base=rowBase(gray,y)
			local target=y*outWidth*4
			for x=0,outWidth-1 do
				local value=buffer.readi16(gray.data,(base+gray.columns[x+1])*2)
				buffer.writeu32(out,target+x*4,value+value*256+value*65536+4278190080)
			end
			if yield then yield() end
		end
	elseif count==3 then
		local transform=true
		if adobe and adobe.transform==0 then transform=false end
		if not adobe and components[1].id==82 and components[2].id==71 and components[3].id==66 then transform=false end
		local first,second,third=planes[1],planes[2],planes[3]
		for y=0,outHeight-1 do
			local baseA=rowBase(first,y)
			local baseB=rowBase(second,y)
			local baseC=rowBase(third,y)
			local target=y*outWidth*4
			for x=0,outWidth-1 do
				local luma=buffer.readi16(first.data,(baseA+first.columns[x+1])*2)
				local chromaB=buffer.readi16(second.data,(baseB+second.columns[x+1])*2)
				local chromaR=buffer.readi16(third.data,(baseC+third.columns[x+1])*2)
				if transform then
					local cb=chromaB-128
					local cr=chromaR-128
					buffer.writeu32(out,target+x*4,clamp8(luma+1.402*cr)+clamp8(luma-0.344136*cb-0.714136*cr)*256+clamp8(luma+1.772*cb)*65536+4278190080)
				else
					buffer.writeu32(out,target+x*4,clamp8(luma)+clamp8(chromaB)*256+clamp8(chromaR)*65536+4278190080)
				end
			end
			if yield then yield() end
		end
	else
		local transform=adobe~=nil and adobe.transform==2
		local first,second,third,fourth=planes[1],planes[2],planes[3],planes[4]
		for y=0,outHeight-1 do
			local baseA=rowBase(first,y)
			local baseB=rowBase(second,y)
			local baseC=rowBase(third,y)
			local baseD=rowBase(fourth,y)
			local target=y*outWidth*4
			for x=0,outWidth-1 do
				local one=buffer.readi16(first.data,(baseA+first.columns[x+1])*2)
				local two=buffer.readi16(second.data,(baseB+second.columns[x+1])*2)
				local three=buffer.readi16(third.data,(baseC+third.columns[x+1])*2)
				local black=buffer.readi16(fourth.data,(baseD+fourth.columns[x+1])*2)
				local cyan,magenta,yellow=one,two,three
				if transform then
					local cb=two-128
					local cr=three-128
					cyan=one+1.402*cr
					magenta=one-0.344136*cb-0.714136*cr
					yellow=one+1.772*cb
				end
				buffer.writeu32(out,target+x*4,clamp8(cyan*black/255)+clamp8(magenta*black/255)*256+clamp8(yellow*black/255)*65536+4278190080)
			end
			if yield then yield() end
		end
	end
	return out
end

function Jpeg.decode(source,options)
	options=options or {}
	local yield=options.yield
	if type(source)=="string" then source=buffer.fromstring(source) end
	if not Jpeg.matches(source) then error("Arquivo JPEG invalido.",0) end
	local total=buffer.len(source)
	local offset=2
	local quantTables={}
	local tablesDC={}
	local tablesAC={}
	local frame,adobe
	local resetInterval=0
	local scans=0
	while offset+1<total do
		local marker=u16(source,offset)
		if marker<65281 or marker==65535 then
			local found,position=findMarker(source,offset,total)
			if not found then break end
			marker=found
			offset=position
		end
		offset+=2
		if marker==65497 then
			break
		elseif marker==65496 or marker==65281 or (marker>=65488 and marker<=65495) then
			continue
		elseif marker==65499 then
			local length=u16(source,offset)
			local finish=offset+length
			if finish>total then error("Arquivo JPEG truncado.",0) end
			local at=offset+2
			while at<finish do
				local spec=buffer.readu8(source,at)
				at+=1
				local precision=bit32.rshift(spec,4)
				if precision>1 then error("Tabela de quantizacao JPEG invalida.",0) end
				local values=buffer.create(128)
				for index=0,63 do
					local value
					if precision==1 then
						value=u16(source,at)
						at+=2
					else
						value=buffer.readu8(source,at)
						at+=1
					end
					buffer.writeu16(values,ZIGZAG[index+1]*2,value)
				end
				quantTables[bit32.band(spec,15)]=values
			end
			offset=finish
		elseif marker==65476 then
			local length=u16(source,offset)
			local finish=offset+length
			if finish>total then error("Arquivo JPEG truncado.",0) end
			local at=offset+2
			while at<finish do
				local spec=buffer.readu8(source,at)
				at+=1
				local counts=table.create(16,0)
				local codes=0
				for index=1,16 do
					local count=buffer.readu8(source,at+index-1)
					counts[index]=count
					codes+=count
				end
				at+=16
				if at+codes>finish then error("Tabela Huffman JPEG truncada.",0) end
				local values=table.create(codes)
				for index=1,codes do values[index]=buffer.readu8(source,at+index-1) end
				at+=codes
				local built=huffmanTable(counts,values)
				if bit32.rshift(spec,4)==0 then
					tablesDC[bit32.band(spec,15)]=built
				else
					tablesAC[bit32.band(spec,15)]=built
				end
			end
			offset=finish
		elseif marker==65501 then
			resetInterval=u16(source,offset+2)
			offset+=u16(source,offset)
		elseif marker==65472 or marker==65473 or marker==65474 then
			if frame then error("JPEG com varias imagens nao suportado.",0) end
			local length=u16(source,offset)
			if offset+length>total then error("Arquivo JPEG truncado.",0) end
			local precision=buffer.readu8(source,offset+2)
			if precision~=8 then error("JPEG com "..precision.." bits por amostra nao suportado.",0) end
			local scanLines=u16(source,offset+3)
			local samplesPerLine=u16(source,offset+5)
			local componentCount=buffer.readu8(source,offset+7)
			if scanLines<1 or samplesPerLine<1 then error("Dimensoes de JPEG invalidas.",0) end
			if samplesPerLine*scanLines>MAX_PIXELS then error("Imagem JPEG grande demais.",0) end
			if componentCount~=1 and componentCount~=3 and componentCount~=4 then error("JPEG com "..componentCount.." componentes nao suportado.",0) end
			frame={progressive=marker==65474,scanLines=scanLines,samplesPerLine=samplesPerLine,components=table.create(componentCount),ids={},maxH=1,maxV=1}
			local at=offset+8
			for index=1,componentCount do
				local id=buffer.readu8(source,at)
				local sampling=buffer.readu8(source,at+1)
				local h=bit32.rshift(sampling,4)
				local v=bit32.band(sampling,15)
				if h<1 or h>4 or v<1 or v>4 then error("Amostragem JPEG invalida.",0) end
				frame.components[index]={id=id,h=h,v=v,quantId=buffer.readu8(source,at+2)}
				frame.ids[id]=index
				if h>frame.maxH then frame.maxH=h end
				if v>frame.maxV then frame.maxV=v end
				at+=3
			end
			prepareComponents(frame)
			offset+=length
		elseif marker==65475 or (marker>=65477 and marker<=65479) or (marker>=65481 and marker<=65483) or (marker>=65485 and marker<=65487) then
			error("Este JPEG usa um modo nao suportado; exporte como JPEG padrao ou progressivo.",0)
		elseif marker==65498 then
			if not frame then error("JPEG sem cabecalho de imagem.",0) end
			local at=offset+2
			local selectors=buffer.readu8(source,at)
			at+=1
			local scanComponents=table.create(selectors)
			for index=1,selectors do
				local id=buffer.readu8(source,at)
				local tables=buffer.readu8(source,at+1)
				local position=frame.ids[id]
				if not position then error("Componente desconhecido na varredura do JPEG.",0) end
				local component=frame.components[position]
				component.tableDC=tablesDC[bit32.rshift(tables,4)]
				component.tableAC=tablesAC[bit32.band(tables,15)]
				scanComponents[index]=component
				at+=2
			end
			local spectralStart=buffer.readu8(source,at)
			local spectralEnd=buffer.readu8(source,at+1)
			local approximation=buffer.readu8(source,at+2)
			at+=3
			local used=decodeScan(source,total,at,frame,scanComponents,resetInterval,spectralStart,spectralEnd,bit32.rshift(approximation,4),bit32.band(approximation,15),yield)
			offset=at+used
			scans+=1
		elseif marker==65518 then
			local length=u16(source,offset)
			if length>=13 and offset+length<=total and buffer.readstring(source,offset+2,5)=="Adobe" then
				adobe={transform=buffer.readu8(source,offset+length-1)}
			end
			offset+=length
		else
			local length=u16(source,offset)
			if length<2 then error("Segmento JPEG invalido.",0) end
			offset+=length
		end
	end
	if not frame then error("JPEG sem cabecalho de imagem.",0) end
	if scans==0 then error("JPEG sem dados comprimidos.",0) end
	for _,component in ipairs(frame.components) do
		local quant=quantTables[component.quantId]
		if not quant then error("Tabela de quantizacao ausente no JPEG.",0) end
		component.quant=quant
	end
	local scratch=buffer.create(256)
	for _,component in ipairs(frame.components) do buildComponentData(component,scratch,yield) end
	local width=frame.samplesPerLine
	local height=frame.scanLines
	local outWidth,outHeight=width,height
	local maxSize=tonumber(options.maxSize)
	if maxSize and maxSize>=16 and (width>maxSize or height>maxSize) then
		local factor=math.min(maxSize/width,maxSize/height)
		outWidth=math.max(1,math.floor(width*factor))
		outHeight=math.max(1,math.floor(height*factor))
	end
	local pixels=linearize(frame,adobe,outWidth,outHeight,yield)
	return {width=outWidth,height=outHeight,pixels=pixels,format="jpeg",hasAlpha=false,sourceWidth=width,sourceHeight=height,progressive=frame.progressive}
end

return Jpeg
