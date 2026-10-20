local Nodes={}

local function identity()
	return {1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1}
end

Nodes.identity=identity

local function finite(value)
	return type(value)=="number" and value==value and value>-math.huge and value<math.huge
end

Nodes.finite=finite

function Nodes.multiply(a,b)
	local out=table.create(16,0)
	for row=0,3 do
		local base=row*4
		for col=1,4 do
			out[base+col]=a[base+1]*b[col]+a[base+2]*b[4+col]+a[base+3]*b[8+col]+a[base+4]*b[12+col]
		end
	end
	return out
end

 
function Nodes.fromArray(values)
	for index=1,16 do assert(finite(values[index]),"Matriz de no invalida no arquivo.") end
	return {values[1],values[5],values[9],values[13],values[2],values[6],values[10],values[14],values[3],values[7],values[11],values[15],values[4],values[8],values[12],values[16]}
end

function Nodes.fromTRS(translation,rotation,scale)
	local tx,ty,tz=0,0,0
	if type(translation)=="table" then
		tx=finite(translation[1]) and translation[1] or 0
		ty=finite(translation[2]) and translation[2] or 0
		tz=finite(translation[3]) and translation[3] or 0
	end
	local x,y,z,w=0,0,0,1
	if type(rotation)=="table" then
		x=finite(rotation[1]) and rotation[1] or 0
		y=finite(rotation[2]) and rotation[2] or 0
		z=finite(rotation[3]) and rotation[3] or 0
		w=finite(rotation[4]) and rotation[4] or 1
	end
	local length=math.sqrt(x*x+y*y+z*z+w*w)
	if length>1e-9 then
		x,y,z,w=x/length,y/length,z/length,w/length
	else
		x,y,z,w=0,0,0,1
	end
	local sx,sy,sz=1,1,1
	if type(scale)=="table" then
		sx=finite(scale[1]) and scale[1] or 1
		sy=finite(scale[2]) and scale[2] or 1
		sz=finite(scale[3]) and scale[3] or 1
	end
	return {
		(1-2*(y*y+z*z))*sx,(2*(x*y-z*w))*sy,(2*(x*z+y*w))*sz,tx,
		(2*(x*y+z*w))*sx,(1-2*(x*x+z*z))*sy,(2*(y*z-x*w))*sz,ty,
		(2*(x*z-y*w))*sx,(2*(y*z+x*w))*sy,(1-2*(x*x+y*y))*sz,tz,
		0,0,0,1,
	}
end

function Nodes.matrix(node)
	if type(node.matrix)=="table" and #node.matrix==16 then return Nodes.fromArray(node.matrix) end
	return Nodes.fromTRS(node.translation,node.rotation,node.scale)
end

function Nodes.point(m,x,y,z)
	return Vector3.new(m[1]*x+m[2]*y+m[3]*z+m[4],m[5]*x+m[6]*y+m[7]*z+m[8],m[9]*x+m[10]*y+m[11]*z+m[12])
end

function Nodes.direction(m,x,y,z)
	return Vector3.new(m[1]*x+m[2]*y+m[3]*z,m[5]*x+m[6]*y+m[7]*z,m[9]*x+m[10]*y+m[11]*z)
end

function Nodes.determinant(m)
	return m[1]*(m[6]*m[11]-m[7]*m[10])-m[2]*(m[5]*m[11]-m[7]*m[9])+m[3]*(m[5]*m[10]-m[6]*m[9])
end

 
function Nodes.inverse(m)
	local a,b,c,tx=m[1],m[2],m[3],m[4]
	local d,e,f,ty=m[5],m[6],m[7],m[8]
	local g,h,i,tz=m[9],m[10],m[11],m[12]
	local det=a*(e*i-f*h)-b*(d*i-f*g)+c*(d*h-e*g)
	if not finite(det) or math.abs(det)<1e-18 then return nil end
	local inv=1/det
	local r1,r2,r3=(e*i-f*h)*inv,(c*h-b*i)*inv,(b*f-c*e)*inv
	local r4,r5,r6=(f*g-d*i)*inv,(a*i-c*g)*inv,(c*d-a*f)*inv
	local r7,r8,r9=(d*h-e*g)*inv,(b*g-a*h)*inv,(a*e-b*d)*inv
	return {
		r1,r2,r3,-(r1*tx+r2*ty+r3*tz),
		r4,r5,r6,-(r4*tx+r5*ty+r6*tz),
		r7,r8,r9,-(r7*tx+r8*ty+r9*tz),
		0,0,0,1,
	}
end

 
 
function Nodes.toCFrame(m)
	local position=Vector3.new(m[4],m[8],m[12])
	if not (finite(m[4]) and finite(m[8]) and finite(m[12])) then position=Vector3.zero end
	local xAxis=Vector3.new(m[1],m[5],m[9])
	local yAxis=Vector3.new(m[2],m[6],m[10])
	local zAxis=Vector3.new(m[3],m[7],m[11])
	if xAxis.Magnitude<1e-9 or yAxis.Magnitude<1e-9 or zAxis.Magnitude<1e-9 then return CFrame.new(position) end
	xAxis=xAxis.Unit
	zAxis=xAxis:Cross(yAxis.Unit)
	if zAxis.Magnitude<1e-9 then return CFrame.new(position) end
	zAxis=zAxis.Unit
	yAxis=zAxis:Cross(xAxis)
	local cframe=CFrame.fromMatrix(position,xAxis,yAxis,zAxis)
	local components={cframe:GetComponents()}
	for _,value in ipairs(components) do
		if not finite(value) then return CFrame.new(position) end
	end
	return cframe
end

 
function Nodes.parents(json)
	local out={}
	for index,node in ipairs(json.nodes or {}) do
		if type(node.children)=="table" then
			for _,child in ipairs(node.children) do
				if type(child)=="number" and out[child]==nil then out[child]=index-1 end
			end
		end
	end
	return out
end

 
function Nodes.global(json,index,parents)
	parents=parents or Nodes.parents(json)
	local nodes=json.nodes or {}
	local matrix=identity()
	local current=index
	local depth=0
	while current~=nil do
		local node=nodes[current+1]
		if type(node)~="table" then break end
		matrix=Nodes.multiply(Nodes.matrix(node),matrix)
		current=parents[current]
		depth+=1
		assert(depth<=512,"Hierarquia do arquivo glTF profunda demais.")
	end
	return matrix
end

 
 
 
function Nodes.placements(json,limit,joints)
	local nodes=json.nodes or {}
	local out={}
	local roots={}
	local scenes=json.scenes
	local scene=scenes and (scenes[(json.scene or 0)+1] or scenes[1])
	if scene and type(scene.nodes)=="table" and #scene.nodes>0 then
		for _,index in ipairs(scene.nodes) do roots[#roots+1]=index end
	else
		local child={}
		for _,node in ipairs(nodes) do
			if type(node.children)=="table" then
				for _,index in ipairs(node.children) do child[index]=true end
			end
		end
		for index=1,#nodes do
			if not child[index-1] then roots[#roots+1]=index-1 end
		end
	end
	local visited={}
	local stack={}
	for index=#roots,1,-1 do stack[#stack+1]={index=roots[index],matrix=identity(),depth=1} end
	while #stack>0 do
		local item=table.remove(stack)
		local node=nodes[item.index+1]
		if node and not visited[item.index] then
			visited[item.index]=true
			assert(item.depth<=(limit or 512),"Hierarquia do arquivo glTF profunda demais.")
			local world=Nodes.multiply(item.matrix,Nodes.matrix(node))
			local joint=item.joint
			if joints and joints[item.index] then joint=item.index end
			if node.mesh~=nil then
				out[#out+1]={mesh=node.mesh,matrix=world,name=node.name,node=item.index,skin=tonumber(node.skin),joint=joint}
			end
			if type(node.children)=="table" then
				 
				for ci=#node.children,1,-1 do stack[#stack+1]={index=node.children[ci],matrix=world,depth=item.depth+1,joint=joint} end
			end
		end
	end
	return out
end

return table.freeze(Nodes)
