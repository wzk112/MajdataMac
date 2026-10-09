#!/usr/bin/env python3
"""Import GPL-3.0 MajdataPlay JudgeAreas.fbx outlines (FBX 7400) and apply Init.unity scale.
Usage: python import-sensor-mesh.py /path/to/MajdataPlay
No Blender runtime is required. The original polygons are used for drawing and hit testing.
"""
import collections,json,math,struct,sys,zlib,re
from pathlib import Path
root=Path(sys.argv[1]); s=(root/'Assets/Models/JudgeAreas.fbx').read_bytes();p=27
assert s[:18]==b'Kaydara FBX Binary' and struct.unpack_from('<I',s,23)[0]==7400

def prop():
 global p
 t=chr(s[p]);p+=1
 def read(fmt):
  global p
  a=struct.unpack_from('<'+fmt,s,p);p+=struct.calcsize('<'+fmt);return a[0] if len(a)==1 else a
 if t in 'YCDFIL':return read({'Y':'h','C':'?','D':'d','F':'f','I':'i','L':'q'}[t])
 if t in 'SR':
  n=read('I');a=s[p:p+n];p+=n;return a.decode('utf8',errors='replace') if t=='S' else ''
 if t in 'fdlibc':
  n,enc,size=read('III');a=s[p:p+size];p+=size
  if enc:a=zlib.decompress(a)
  return list(struct.unpack('<'+str(n)+{'f':'f','d':'d','l':'q','i':'i','b':'?','c':'b'}[t],a))
 raise ValueError(t)
def node():
 global p
 end,n,size,nlen=struct.unpack_from('<IIIB',s,p);p+=13
 if not end:return None
 name=s[p:p+nlen].decode();p+=nlen
 props=[prop() for _ in range(n)]; children=[]
 while p<end:
  x=node()
  if x:children.append(x)
 p=end
 return dict(name=name,props=props,children=children)
nodes=[]
while p<len(s):
 n=node()
 if n is None:break
 nodes.append(n)
objects=next(x for x in nodes if x['name']=='Objects')['children']
connections=next(x for x in nodes if x['name']=='Connections')['children']
models={x['props'][0]:x['props'][1].split('\x00')[0] for x in objects if x['name']=='Model'}
parents={x['props'][1]:x['props'][2] for x in connections}
scene=(root/'Assets/Scenes/Init.unity').read_text(encoding='utf-8-sig')
scale=float(re.search(r'fileID: -8679921383154817045[^\n]*\n      propertyPath: m_LocalScale.x\n      value: ([\d.]+)',scene)[1])*100
outlines={}
for geometry in objects:
 if geometry['name']!='Geometry':continue
 group=models[parents[geometry['props'][0]]]
 children={x['name']:x['props'] for x in geometry['children']}
 values=children['Vertices'][0]; vertices=[(values[i],values[i+1]) for i in range(0,len(values),3)]
 faces=[];face=[]
 for v in children['PolygonVertexIndex'][0]:
  face.append(v if v>=0 else -v-1)
  if v<0:faces.append(face);face=[]
 edges=collections.Counter(tuple(sorted((face[i],face[(i+1)%len(face)]))) for face in faces for i in range(len(face)))
 adjacent=collections.defaultdict(list)
 for (a,b),count in edges.items():
  if count==1:adjacent[a].append(b);adjacent[b].append(a)
 start=next(iter(adjacent)); indices=[start];prev=-1;current=start
 while True:
  nxt=next(v for v in adjacent[current] if v!=prev)
  if nxt==start:break
  indices.append(nxt);prev,current=current,nxt
 outlines[group]=[(vertices[i][0]*scale,-vertices[i][1]*scale) for i in indices]
regions=[]
for group,base in outlines.items():
 if group=='C':
  for side in [1,-1]:regions.append(dict(id=16,name='C1' if side==1 else 'C2',vertices=[dict(x=x*side,y=y) for x,y in base]))
 else:
  origin=2 if group in ['A','B'] else 3
  offset={'A':0,'B':8,'D':17,'E':25}[group]
  for lane in range(1,9):
   a=(lane-origin)*math.pi/4;c=math.cos(a);sn=math.sin(a)
   regions.append(dict(id=offset+lane-1,name=f'{group}{lane}',vertices=[dict(x=x*c-y*sn,y=x*sn+y*c) for x,y in base]))
regions.sort(key=lambda x:(x['id'],x['name']))
assert len(regions)==34 and len({x['id'] for x in regions})==33
project=Path(__file__).resolve().parents[1]
(project/'Sources/MajdataCore/Resources/sensor-polygons.json').write_text(json.dumps(regions,separators=(',',':')))
print('Imported 34 mesh outlines / 33 logical sensors; world scale',scale)
