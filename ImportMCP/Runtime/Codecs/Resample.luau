local Resample={}

local CHANNEL={1,256,65536,16777216}

local function box(source,width,height,targetWidth,targetHeight,yield)
	local out=buffer.create(targetWidth*targetHeight*4)
	local ratioX=width/targetWidth
	local ratioY=height/targetHeight
	for y=0,targetHeight-1 do
		local startY=math.floor(y*ratioY)
		local stopY=math.min(height,math.max(startY+1,math.ceil((y+1)*ratioY)))
		local target=y*targetWidth*4
		for x=0,targetWidth-1 do
			local startX=math.floor(x*ratioX)
			local stopX=math.min(width,math.max(startX+1,math.ceil((x+1)*ratioX)))
			local sumR,sumG,sumB,sumA,count=0,0,0,0,0
			for sampleY=startY,stopY-1 do
				local base=sampleY*width*4
				for sampleX=startX,stopX-1 do
					local at=base+sampleX*4
					sumR+=buffer.readu8(source,at)
					sumG+=buffer.readu8(source,at+1)
					sumB+=buffer.readu8(source,at+2)
					sumA+=buffer.readu8(source,at+3)
					count+=1
				end
			end
			if count==0 then count=1 end
			buffer.writeu32(out,target+x*4,math.floor(sumR/count+0.5)+math.floor(sumG/count+0.5)*256+math.floor(sumB/count+0.5)*65536+math.floor(sumA/count+0.5)*16777216)
		end
		if yield then yield() end
	end
	return out
end

local function bilinear(source,width,height,targetWidth,targetHeight,yield)
	local out=buffer.create(targetWidth*targetHeight*4)
	local ratioX=width/targetWidth
	local ratioY=height/targetHeight
	for y=0,targetHeight-1 do
		local positionY=math.max(0,(y+0.5)*ratioY-0.5)
		local topRow=math.min(height-1,math.floor(positionY))
		local bottomRow=math.min(height-1,topRow+1)
		local weightY=positionY-topRow
		local topBase=topRow*width*4
		local bottomBase=bottomRow*width*4
		local target=y*targetWidth*4
		for x=0,targetWidth-1 do
			local positionX=math.max(0,(x+0.5)*ratioX-0.5)
			local leftColumn=math.min(width-1,math.floor(positionX))
			local rightColumn=math.min(width-1,leftColumn+1)
			local weightX=positionX-leftColumn
			local topLeft=topBase+leftColumn*4
			local topRight=topBase+rightColumn*4
			local bottomLeft=bottomBase+leftColumn*4
			local bottomRight=bottomBase+rightColumn*4
			local packed=0
			for channel=0,3 do
				local a=buffer.readu8(source,topLeft+channel)
				local b=buffer.readu8(source,topRight+channel)
				local c=buffer.readu8(source,bottomLeft+channel)
				local d=buffer.readu8(source,bottomRight+channel)
				local top=a+(b-a)*weightX
				local bottom=c+(d-c)*weightX
				local value=math.floor(top+(bottom-top)*weightY+0.5)
				if value<0 then value=0 elseif value>255 then value=255 end
				packed+=value*CHANNEL[channel+1]
			end
			buffer.writeu32(out,target+x*4,packed)
		end
		if yield then yield() end
	end
	return out
end

function Resample.scale(image,targetWidth,targetHeight,options)
	options=options or {}
	local yield=options.yield
	local width,height=image.width,image.height
	local pixels=image.pixels
	if targetWidth<1 or targetHeight<1 then error("Tamanho de destino invalido.",0) end
	local middleWidth=math.max(1,math.min(width,targetWidth))
	local middleHeight=math.max(1,math.min(height,targetHeight))
	if middleWidth~=width or middleHeight~=height then
		pixels=box(pixels,width,height,middleWidth,middleHeight,yield)
		width,height=middleWidth,middleHeight
	end
	if width~=targetWidth or height~=targetHeight then
		pixels=bilinear(pixels,width,height,targetWidth,targetHeight,yield)
	end
	if pixels==image.pixels then
		local copy=buffer.create(buffer.len(pixels))
		buffer.copy(copy,0,pixels,0,buffer.len(pixels))
		pixels=copy
	end
	return {width=targetWidth,height=targetHeight,pixels=pixels,format=image.format,hasAlpha=image.hasAlpha,
		sourceWidth=image.sourceWidth or image.width,sourceHeight=image.sourceHeight or image.height,
		resized=(targetWidth~=(image.sourceWidth or image.width) or targetHeight~=(image.sourceHeight or image.height))}
end

return Resample
