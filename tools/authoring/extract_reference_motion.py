"""Read supplied glTF motion in Blender's mathutils; export skeleton-space samples.
No reference meshes or runtime animation code are copied into the player.
"""
import json,struct,pathlib,math,bisect
from mathutils import Matrix,Vector,Quaternion
ROOT=pathlib.Path(__file__).resolve().parents[2]
IN=ROOT/'tools/.local/pose-references';OUT=ROOT/'assets/characters/pose_sources';OUT.mkdir(parents=True,exist_ok=True)

def vec(v):return [round(float(x),7) for x in v]
def basis(m):return [vec(m.col[i]) for i in range(3)]
class Gltf:
 def __init__(self,p):
  self.g=json.loads(p.read_text());self.buffers=[(p.parent/b['uri']).read_bytes() for b in self.g['buffers']];self.nodes=self.g['nodes'];self.cache={}
  self.parents={c:i for i,n in enumerate(self.nodes) for c in n.get('children',[])}
  self.names={n.get('name',''):i for i,n in enumerate(self.nodes)}
 def find(self,p):return next(i for n,i in self.names.items() if n.startswith(p+'_') or n==p)
 def acc(self,i):
  if i in self.cache:return self.cache[i]
  a=self.g['accessors'][i];v=self.g['bufferViews'][a['bufferView']];num={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']];f={5126:'f',5125:'I',5123:'H',5121:'B'}[a['componentType']];size=struct.calcsize(f)*num;off=v.get('byteOffset',0)+a.get('byteOffset',0);stride=v.get('byteStride',size)
  r=[struct.unpack_from('<'+f*num,self.buffers[v['buffer']],off+j*stride) for j in range(a['count'])];self.cache[i]=r;return r
 def worlds(self,anim=None,t=0):
  values={}
  if anim:
   for c in anim['channels']:
    s=anim['samplers'][c['sampler']];times=[x[0] for x in self.acc(s['input'])];ks=self.acc(s['output']);i=max(0,min(len(times)-2,bisect.bisect_right(times,t)-1));w=max(0,min(1,(t-times[i])/max(1e-8,times[min(i+1,len(times)-1)]-times[i])));a=ks[i];b=ks[min(i+1,len(ks)-1)]
    if c['target']['path']=='rotation':q=Quaternion((a[3],*a[:3])).slerp(Quaternion((b[3],*b[:3])),w);val=(q.x,q.y,q.z,q.w)
    else:val=tuple(x*(1-w)+y*w for x,y in zip(a,b))
    values[(c['target']['node'],c['target']['path'])]=val
  out={}
  def world(i):
   if i in out:return out[i]
   n=self.nodes[i]
   if 'matrix' in n:m=Matrix([n['matrix'][k:k+4] for k in range(0,16,4)]).transposed()
   else:
    pos=values.get((i,'translation'),n.get('translation',(0,0,0)));q=values.get((i,'rotation'),n.get('rotation',(0,0,0,1)));sc=values.get((i,'scale'),n.get('scale',(1,1,1)))
    m=Matrix.LocRotScale(Vector(pos),Quaternion((q[3],*q[:3])),Vector(sc))
   out[i]=(world(self.parents[i])@m) if i in self.parents else m;return out[i]
  for i in range(len(self.nodes)):world(i)
  return out
 def rest(self):
  worlds=self.worlds();skin=self.g['skins'][0];mesh=next(i for i,n in enumerate(self.nodes) if n.get('skin')==0);out={}
  for j,v in zip(skin['joints'],self.acc(skin['inverseBindMatrices'])):out[j]=worlds[mesh]@Matrix([v[k:k+4] for k in range(0,16,4)]).transposed().inverted()
  return out

def mapping(label,g,side):
 s=side[0].lower();S=side[0]
 if label=='rifle':arm=[f'{s}_upperarm',f'{s}_forearm',f'{s}_wrist'];fs={f:[f'{s}_{f.lower()}_{k}' for k in ['low','mid','tip']] for f in ['Thumb','Index','Middle','Ring','Pinky']}
 elif label=='knife_pose':arm=[f'UpperArm.{S}',f'LowerArm.{S}',f'Hand.{S}'];fs={f:[f'{f}_{k}.{S}' for k in range(3)] for f in ['Thumb','Index','Middle','Ring','Pinky']}
 else:
  arm=[f'upperarm_L.{S}',f'lowerarm_L.{S}',f'hand_L.{S}'];fs={}
  for f in ['Thumb','Index','Middle','Ring','Pinky']:
   p='pink' if f=='Pinky' else f.lower()
   fs[f]=[f'{p}_L.{S}',f'{p}_L.002.{S}',f'{p}_L.001.{S}'] if f=='Thumb' else [f'{p}_L.003.{S}',f'{p}_L.002.{S}',f'{p}_L.001.{S}'] if f!='Ring' else [f'{p}_L.001.{S}',f'{p}_L.002.{S}',f'{p}_L.003.{S}']
 def terminal(p):
  n=g.find(p);return g.nodes[n]['children'][0]
 return [g.find(p) for p in arm],{f:[g.find(p) for p in ps]+[terminal(ps[-1])] for f,ps in fs.items()}

def export(label):
 g=Gltf(IN/label/'scene.gltf');rest=g.rest();maps={s:mapping(label,g,s) for s in ['Right','Left']}
 w=g.worlds();right=maps['Right'][0][0];left=maps['Left'][0][0];x=(w[right].translation-w[left].translation);x.z=0;x.y=0;x.normalize();y=Vector((0,1,0));z=x.cross(y);turn=Matrix((x,y,z)) # rows -> world to canonical
 frames={};handframes={}
 for side,(arm,fingers) in maps.items():
  wrist=arm[2];yy=(rest[fingers['Middle'][0]].translation-rest[wrist].translation).normalized();xx=(rest[fingers['Index'][0]].translation-rest[fingers['Pinky'][0]].translation)*(1 if side=='Right' else -1);xx=(xx-yy*xx.dot(yy)).normalized();handframes[side]=Matrix((xx,yy,xx.cross(yy))).transposed()
 for a in g.g['animations']:
  duration=max(g.acc(s['input'])[-1][0] for s in a['samplers']);n=math.ceil(duration*30);samples=[]
  for frame in range(n+1):
   poses=g.worlds(a,frame*duration/n);sample={}
   for side,(arm,fingers) in maps.items():
    shoulder,elbow,wrist=[poses[j].translation for j in arm];length=(shoulder-elbow).length+(elbow-wrist).length;sc=.56/length
    frame_world=poses[arm[2]].to_quaternion().to_matrix()@rest[arm[2]].to_quaternion().to_matrix().inverted()@handframes[side]
    dirs={f:[vec(frame_world.inverted()@(poses[chain[k+1]].translation-poses[chain[k]].translation).normalized()) for k in range(3)] for f,chain in fingers.items()}
    sample[side]={'wrist':vec(turn@(wrist-shoulder)*sc),'elbow':vec(turn@(elbow-shoulder)*sc),'palm':basis(turn@frame_world),'fingers':dirs}
   samples.append(sample)
  frames[a['name']]={'duration':duration,'frames':samples}
 print('EXPORTED',label,list(frames), 'first',next(iter(frames.values()))['frames'][0]['Right'])
 (OUT/(label+'.json')).write_text(json.dumps(frames,separators=(',',':')))
 (OUT/(label+'_license.txt')).write_bytes((IN/label/'license.txt').read_bytes())
for label in ['rifle','pistol','knife_pose']:export(label)
