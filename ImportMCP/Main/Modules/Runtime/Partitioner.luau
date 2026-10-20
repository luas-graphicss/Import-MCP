local Limits=require(script.Parent.Limits)
local P={}
function P.split(vertexCount,triangleCount,getVertices,options)
 options=options or {}
 local maxV=options.vertices or Limits.CHUNK_VERTICES
 local maxT=options.triangles or Limits.CHUNK_TRIANGLES
 assert(maxV>=3 and maxV<=55000 and maxT>=1 and maxT<=18000,"Limites fisicos de chunk invalidos.")
 assert(vertexCount>=0 and vertexCount<=Limits.VERTICES and triangleCount>=0 and triangleCount<=Limits.TRIANGLES,"Objeto excede a capacidade logica.")
 local yieldFn=options.yieldFn
 local islandBreak=options.islandBreak
 local every=Limits.YIELD_EVERY
 local function pause(i) if yieldFn and i%every==0 then yieldFn() end end
 local head,nextLink={},table.create(triangleCount*3)
 local incident=table.create(triangleCount*3)
 local link=0
 local function check(v)
  assert(v%1==0 and v>=1 and v<=vertexCount,"Indice fora do documento.")
 end
 for ti=1,triangleCount do
  local a,b,c=getVertices(ti)
  assert(a and b and c and a~=b and b~=c and a~=c,"Triangulo invalido no particionador.")
  check(a); check(b); check(c)
  link+=1; incident[link]=ti; nextLink[link]=head[a]; head[a]=link
  link+=1; incident[link]=ti; nextLink[link]=head[b]; head[b]=link
  link+=1; incident[link]=ti; nextLink[link]=head[c]; head[c]=link
  pause(ti)
 end
 local chunks,seen,expanded,queue={},{},{},{}
 local front,tail,seed,processed=1,0,1,0
 local current
 local vertexTotal,triangleTotal=0,0
 local function fresh()
  current={vertices={},triangles={},localIndex={}}
  vertexTotal,triangleTotal=0,0
  chunks[#chunks+1]=current
 end
 local function enqueue(ti)
  if not seen[ti] then seen[ti]=true; tail+=1; queue[tail]=ti end
 end
 local function place(v)
  local index=current.localIndex
  if not index[v] then
   vertexTotal+=1
   current.vertices[vertexTotal]=v
   index[v]=vertexTotal
  end
  if not expanded[v] then
   expanded[v]=true
   local at=head[v]
   while at do enqueue(incident[at]); at=nextLink[at] end
  end
 end
 while processed<triangleCount do
  if front>tail then
   while seen[seed] do seed+=1 end
   enqueue(seed)
   if current and islandBreak and triangleTotal>=islandBreak then current=nil end
  end
  local ti=queue[front]; queue[front]=nil; front+=1
  local a,b,c=getVertices(ti)
  if not current then fresh() end
  local index=current.localIndex
  local extra=0
  if not index[a] then extra+=1 end
  if not index[b] then extra+=1 end
  if not index[c] then extra+=1 end
  if triangleTotal>=maxT or vertexTotal+extra>maxV then fresh() end
  place(a); place(b); place(c)
  triangleTotal+=1
  current.triangles[triangleTotal]=ti
  processed+=1; pause(processed)
 end
 return chunks
end
function P.bounds(vertices,ids)
 local total=#ids
 assert(total>0,"Chunk sem vertices.")
 local lo=vertices[ids[1]]
 local hi=lo
 for i=1,total do
  local p=vertices[ids[i]]
  lo=lo:Min(p); hi=hi:Max(p)
 end
 return (lo+hi)*0.5,hi-lo
end
return table.freeze(P)
