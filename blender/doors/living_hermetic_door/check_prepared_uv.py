import bpy, json, numpy as np, struct
from pathlib import Path
root=Path(__file__).resolve().parent
bpy.ops.wm.open_mainfile(filepath=str(root/'living_hermetic_door_prepared.blend'))
meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
triangles=[]
for o in meshes:
    layer=o.data.uv_layers.active.data
    o.data.calc_loop_triangles()
    for p in o.data.loop_triangles: triangles.append([tuple(layer[i].uv) for i in p.loops])
triangles=np.array(triangles,dtype=np.float64)
grid={}; pairs=set()
for i,t in enumerate(triangles):
    low=np.floor(t.min(0)*128).astype(int); high=np.floor(t.max(0)*128).astype(int)
    for x in range(low[0],high[0]+1):
        for y in range(low[1],high[1]+1):
            cell=grid.setdefault((x,y),[])
            for j in cell: pairs.add((j,i))
            cell.append(i)
selected=0
pairs=list(pairs)
for start in range(0,len(pairs),20000):
    indices=np.array(pairs[start:start+20000]); a=triangles[indices[:,0]]; b=triangles[indices[:,1]]
    edges=np.concatenate((np.roll(a,-1,axis=1)-a,np.roll(b,-1,axis=1)-b),axis=1)
    axes=np.stack((-edges[:,:,1],edges[:,:,0]),axis=-1)
    axes/=np.maximum(np.linalg.norm(axes,axis=2,keepdims=True),1e-20)
    pa=np.einsum('nvc,nac->nva',a,axes); pb=np.einsum('nvc,nac->nva',b,axes)
    depth=np.minimum(pa.max(1),pb.max(1))-np.maximum(pa.min(1),pb.min(1))
    selected+=int(np.all(depth>1e-9,axis=1).sum())
report=json.loads((root/'prepared_validation.json').read_text())
report['uv_overlapping_triangle_pairs']=selected
report['all_images_2k']=all(tuple(i.size)==(2048,2048) for i in bpy.data.images if i.type=='IMAGE')
glb=root.parents[2]/'assets/models/doors/living_hermetic_door/living_hermetic_door.glb'
data=glb.read_bytes(); length=struct.unpack_from('<I',data,12)[0]; doc=json.loads(data[20:20+length])
report['glb_bytes']=len(data)
report['glb_cameras']=len(doc.get('cameras',[])); report['glb_animations']=len(doc.get('animations',[]))
report['glb_materials']=[m['name'] for m in doc['materials']]
report['glb_textures_embedded']=all('bufferView' in i for i in doc['images'])
report['glb_textured_primitives_have_tangents']=all('TANGENT' in p['attributes'] for m in doc['meshes'] for p in m['primitives'] if 'normalTexture' in doc['materials'][p['material']])
assert report['glb_textures_embedded'] and report['glb_textured_primitives_have_tangents']
assert report['glb_cameras']==report['glb_animations']==0
(root/'prepared_validation.json').write_text(json.dumps(report,indent=2))
print('UV_VALIDATION',selected,'overlapping triangle pairs')
assert selected==0

