local Limits=require(script.Parent.Parent.Runtime.Limits)

 
 
 
local Probe={}

 
Probe.AUDIO={mp3={mime="audio/mpeg",ext="mp3"},ogg={mime="audio/ogg",ext="ogg"},wav={mime="audio/wav",ext="wav"},flac={mime="audio/flac",ext="flac"}}
Probe.VIDEO={mp4={mime="video/mp4",ext="mp4"},mov={mime="video/quicktime",ext="mov"}}

local function u32be(data,at) return buffer.readu8(data,at)*16777216+buffer.readu8(data,at+1)*65536+buffer.readu8(data,at+2)*256+buffer.readu8(data,at+3) end
local function u24be(data,at) return buffer.readu8(data,at)*65536+buffer.readu8(data,at+1)*256+buffer.readu8(data,at+2) end
local function u64be(data,at) return u32be(data,at)*4294967296+u32be(data,at+4) end
local function u64le(data,at) return buffer.readu32(data,at)+buffer.readu32(data,at+4)*4294967296 end
local function tag(data,at,length)
	if at<0 or at+length>buffer.len(data) then return "" end
	return buffer.readstring(data,at,length)
end

local MPEG_BITRATES={
	[1]={0,32,64,96,128,160,192,224,256,288,320,352,384,416,448},  
	[2]={0,32,48,56,64,80,96,112,128,160,192,224,256,320,384},  
	[3]={0,32,40,48,56,64,80,96,112,128,160,192,224,256,320},  
	[4]={0,32,48,56,64,80,96,112,128,144,160,176,192,224,256},  
	[5]={0,8,16,24,32,40,48,56,64,80,96,112,128,144,160},  
}
local MPEG_RATES={[3]={44100,48000,32000},[2]={22050,24000,16000},[0]={11025,12000,8000}}

local function mp3Frame(data,at)
	if at+4>buffer.len(data) then return nil end
	local b1,b2,b3=buffer.readu8(data,at),buffer.readu8(data,at+1),buffer.readu8(data,at+2)
	if b1~=0xFF or b2<0xE0 then return nil end
	local version=(b2//8)%4  
	local layerBits=(b2//2)%4  
	if version==1 or layerBits==0 then return nil end
	local layer=4-layerBits
	local bitrateIndex=b3//16
	local rateIndex=(b3//4)%4
	if bitrateIndex==0 or bitrateIndex==15 or rateIndex==3 then return nil end
	local table_
	if version==3 then table_=MPEG_BITRATES[layer] elseif layer==1 then table_=MPEG_BITRATES[4] else table_=MPEG_BITRATES[5] end
	local bitrate=table_[bitrateIndex+1]*1000
	local sampleRate=MPEG_RATES[version][rateIndex+1]
	local padding=(b3//2)%2
	local samples
	if layer==1 then samples=384 elseif layer==2 or version==3 then samples=1152 else samples=576 end
	local length
	if layer==1 then length=(12*bitrate//sampleRate+padding)*4 else length=samples//8*bitrate//sampleRate+padding end
	if length<=4 then return nil end
	local channelMode=(buffer.readu8(data,at+3)//64)%4
	return {bitrate=bitrate,sampleRate=sampleRate,samples=samples,length=length,channels=channelMode==3 and 1 or 2,version=version,layer=layer}
end

local function probeMp3(data,info)
	local size=buffer.len(data)
	local at=0
	if tag(data,0,3)=="ID3" and size>=10 then
		local b6,b7,b8,b9=buffer.readu8(data,6),buffer.readu8(data,7),buffer.readu8(data,8),buffer.readu8(data,9)
		at=10+((b6*128+b7)*128+b8)*128+b9
		if (buffer.readu8(data,5)//16)%2==1 then at+=10 end
	end
	local frame
	local limit=math.min(size-4,at+65536)
	while at<limit do
		frame=mp3Frame(data,at)
		if frame and mp3Frame(data,at+frame.length) then break end
		frame=nil
		at+=1
	end
	if not frame then return nil end
	info.sampleRate=frame.sampleRate
	info.channels=frame.channels
	info.bitrate=frame.bitrate
	local xingAt=at+4+((frame.version==3) and (frame.channels==1 and 17 or 32) or (frame.channels==1 and 9 or 17))
	local marker=tag(data,xingAt,4)
	if (marker=="Xing" or marker=="Info") and xingAt+16<=size then
		local flags=u32be(data,xingAt+4)
		if flags%2==1 then
			local frames=u32be(data,xingAt+8)
			info.vbr=marker=="Xing"
			info.duration=frames*frame.samples/frame.sampleRate
		end
	end
	if not info.duration then
		local audioBytes=size-at
		local tail=tag(data,size-128,3)
		if tail=="TAG" then audioBytes-=128 end
		info.duration=audioBytes*8/frame.bitrate
	end
	return true
end

local function probeWav(data,info)
	local size=buffer.len(data)
	local at=12
	local byteRate,dataSize
	while at+8<=size do
		local id=tag(data,at,4)
		local length=buffer.readu32(data,at+4)
		if id=="fmt " and at+24<=size then
			info.codec=buffer.readu16(data,at+8)==1 and "pcm" or ("wav-format-"..buffer.readu16(data,at+8))
			info.channels=buffer.readu16(data,at+10)
			info.sampleRate=buffer.readu32(data,at+12)
			byteRate=buffer.readu32(data,at+16)
			info.bitsPerSample=buffer.readu16(data,at+22)
		elseif id=="data" then
			dataSize=math.min(length,size-at-8)
			if length==0 or length==0xFFFFFFFF then dataSize=size-at-8 end
		end
		at+=8+length+(length%2)
		if length==0xFFFFFFFF then break end
	end
	if byteRate and byteRate>0 and dataSize then info.duration=dataSize/byteRate end
	info.bitrate=byteRate and byteRate*8 or nil
	return true
end

local function probeFlac(data,info)
	 
	if buffer.len(data)<42 then return true end
	local at=8
	local rateHi=u24be(data,at+10)  
	info.sampleRate=rateHi//16
	info.channels=(rateHi//2)%8+1
	local bpsHi=rateHi%2
	local b13=buffer.readu8(data,at+13)
	info.bitsPerSample=bpsHi*16+b13//16+1
	local totalSamples=(b13%16)*4294967296+u32be(data,at+14)
	if info.sampleRate>0 and totalSamples>0 then info.duration=totalSamples/info.sampleRate end
	return true
end

local function probeOgg(data,info)
	local size=buffer.len(data)
	local header=tag(data,28,8)
	local granuleRate
	if header:sub(1,7)=="\1vorbis" then
		info.codec="vorbis"
		info.channels=buffer.readu8(data,39)
		info.sampleRate=buffer.readu32(data,40)
		info.bitrate=buffer.readi32(data,48)
		if info.bitrate<=0 then info.bitrate=nil end
		granuleRate=info.sampleRate
	elseif header=="OpusHead" then
		info.codec="opus"
		info.channels=buffer.readu8(data,37)
		info.sampleRate=buffer.readu32(data,40)
		granuleRate=48000
	elseif header:sub(1,5)=="\127FLAC" then
		info.codec="flac-in-ogg"
	else
		info.codec="ogg"
	end
	 
	local scanFrom=math.max(0,size-262144)
	local tail=buffer.readstring(data,scanFrom,size-scanFrom)
	local lastPage
	local at=0
	while true do
		local found=tail:find("OggS",at+1,true)
		if not found then break end
		lastPage=scanFrom+found-1
		at=found
	end
	if lastPage and lastPage+14<=size and granuleRate and granuleRate>0 then
		local granule=u64le(data,lastPage+6)
		if granule>0 and granule<2^53 then info.duration=granule/granuleRate end
	end
	return true
end

local function readBoxes(data,from,to,visit)
	local at=from
	while at+8<=to do
		local size=u32be(data,at)
		local kind=tag(data,at+4,4)
		local headerSize=8
		if size==1 then
			if at+16>to then break end
			size=u64be(data,at+8)
			headerSize=16
		elseif size==0 then
			size=to-at
		end
		if size<headerSize then break end
		local stop=visit(kind,at+headerSize,math.min(at+size,to))
		if stop then return true end
		at+=size
	end
	return false
end

local function probeMp4(data,info)
	local size=buffer.len(data)
	info.brand=tag(data,8,4):gsub("[%c%s]","")
	local tracks={}
	readBoxes(data,0,size,function(kind,from,to)
		if kind=="moov" then
			readBoxes(data,from,to,function(child,cFrom,cTo)
				if child=="mvhd" and cFrom+20<=cTo then
					local version=buffer.readu8(data,cFrom)
					local timescale,duration
					if version==1 then
						timescale=u32be(data,cFrom+20)
						duration=u64be(data,cFrom+24)
					else
						timescale=u32be(data,cFrom+12)
						duration=u32be(data,cFrom+16)
					end
					if timescale>0 then info.duration=duration/timescale end
				elseif child=="trak" then
					local track={}
					readBoxes(data,cFrom,cTo,function(t,tFrom,tTo)
						if t=="tkhd" and tTo-tFrom>=84 then
							local version=buffer.readu8(data,tFrom)
							track.width=u32be(data,tTo-8)/65536
							track.height=u32be(data,tTo-4)/65536
							track.id=u32be(data,version==1 and tFrom+20 or tFrom+12)
						elseif t=="mdia" then
							readBoxes(data,tFrom,tTo,function(m,mFrom,mTo)
								if m=="hdlr" and mFrom+12<=mTo then
									track.handler=tag(data,mFrom+8,4)
								elseif m=="mdhd" and mFrom+20<=mTo then
									local version=buffer.readu8(data,mFrom)
									if version==1 then
										track.timescale=u32be(data,mFrom+20)
									else
										track.timescale=u32be(data,mFrom+12)
									end
								end
							end)
						end
					end)
					tracks[#tracks+1]=track
				end
			end)
			return true
		end
	end)
	for _,track in ipairs(tracks) do
		if track.handler=="vide" then
			info.hasVideo=true
			if (track.width or 0)>0 then
				info.width=math.round(track.width)
				info.height=math.round(track.height)
			end
		elseif track.handler=="soun" then
			info.hasAudio=true
			info.sampleRate=info.sampleRate or track.timescale
		end
	end
	info.tracks=#tracks
	return true
end

 
 
function Probe.inspect(data,fileName)
	assert(typeof(data)=="buffer","Probe requer buffer.")
	local size=buffer.len(data)
	if size<12 then return nil,"arquivo pequeno demais" end
	local head4=tag(data,0,4)
	local info={bytes=size,fileName=fileName}
	local lowered=string.lower(tostring(fileName or ""))
	if head4=="RIFF" and tag(data,8,4)=="WAVE" then
		info.kind,info.format="audio","wav"
		probeWav(data,info)
	elseif head4=="fLaC" then
		info.kind,info.format="audio","flac"
		probeFlac(data,info)
	elseif head4=="OggS" then
		info.kind,info.format="audio","ogg"
		probeOgg(data,info)
	elseif tag(data,4,4)=="ftyp" or tag(data,4,4)=="moov" or tag(data,4,4)=="mdat" or tag(data,4,4)=="wide" or tag(data,4,4)=="free" then
		probeMp4(data,info)
		local brand=string.lower(info.brand or "")
		if info.hasVideo then
			info.kind="video"
			info.format=(brand:sub(1,2)=="qt" or lowered:match("%.mov$")) and "mov" or "mp4"
		else
			info.kind="audio"
			info.format=lowered:match("%.m4a$") and "m4a" or "mp4-audio"
		end
	elseif head4=="\26\69\223\163" then
		info.kind="video"
		info.format=lowered:match("%.mkv$") and "mkv" or "webm"
	elseif tag(data,0,3)=="ID3" or (buffer.readu8(data,0)==0xFF and buffer.readu8(data,1)>=0xE0) then
		info.kind,info.format="audio","mp3"
		if not probeMp3(data,info) then return nil,"MP3 sem quadros validos" end
	elseif lowered:match("%.mp3$") then
		info.kind,info.format="audio","mp3"
		if not probeMp3(data,info) then return nil,"MP3 sem quadros validos" end
	else
		return nil,"formato nao reconhecido"
	end
	local supported=(info.kind=="audio" and Probe.AUDIO[info.format]) or (info.kind=="video" and Probe.VIDEO[info.format])
	info.supported=supported~=nil
	if supported then
		info.mime=supported.mime
		info.ext=supported.ext
	end
	if info.duration then info.duration=math.round(info.duration*1000)/1000 end
	return info
end

 
function Probe.problems(info)
	local problems={}
	if not info.supported then
		if info.kind=="audio" then
			problems[#problems+1]="Formato de audio '"..tostring(info.format).."' nao aceito pela Roblox; converta para MP3, OGG, WAV ou FLAC."
		else
			problems[#problems+1]="Formato de video '"..tostring(info.format).."' nao aceito pela Roblox; converta para MP4 (H.264/AAC) ou MOV."
		end
	end
	if info.kind=="audio" then
		if info.bytes>Limits.MAX_AUDIO_BYTES then problems[#problems+1]=string.format("Audio com %.1f MiB; a Roblox aceita ate %d MiB.",info.bytes/1048576,Limits.MAX_AUDIO_BYTES//1048576) end
		if info.duration and info.duration>Limits.AUDIO_MAX_SECONDS then problems[#problems+1]=string.format("Audio com %.0f s; o limite e %d s (7 min).",info.duration,Limits.AUDIO_MAX_SECONDS) end
	else
		if info.duration and info.duration>Limits.VIDEO_MAX_SECONDS then problems[#problems+1]=string.format("Video com %.0f s; o limite e %d s (5 min).",info.duration,Limits.VIDEO_MAX_SECONDS) end
		if (info.width or 0)>Limits.VIDEO_MAX_WIDTH or (info.height or 0)>Limits.VIDEO_MAX_HEIGHT then problems[#problems+1]=string.format("Video %dx%d acima de 4K.",info.width or 0,info.height or 0) end
	end
	return problems
end

 
function Probe.kindFromName(fileName)
	local lowered=string.lower(tostring(fileName or ""))
	local ext=lowered:match("%.(%w+)$")
	if not ext then return nil end
	if Probe.AUDIO[ext] or ext=="m4a" or ext=="aac" or ext=="wma" then return "audio" end
	if Probe.VIDEO[ext] or ext=="webm" or ext=="mkv" or ext=="avi" then return "video" end
	return nil
end

return table.freeze(Probe)
