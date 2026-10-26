import bpy,numpy as np,json,struct
from pathlib import Path
ROOT=Path(__file__).resolve().parent
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'medical_hermetic_door_realistic_2k.blend'))
report=json.loads((ROOT/'realistic_validation.json').read_text())
for name in ['frame','doors']:
    triangles=[]
    for o in bpy.context.scene.objects:
        if o.type!='MESH' or 'Lenses' in o.name:continue
        if ('Leaf' in o.name)!=(name=='doors'):continue
        uv=o.data.uv_layers.active.data;o.data.calc_loop_triangles()
        triangles.extend([[tuple(uv[i].uv) for i in tri.loops] for tri in o.data.loop_triangles])
    t=np.array(triangles);grid={};pairs=set()
    for i,tri in enumerate(t):
        lo=np.floor(tri.min(0)*64).astype(int);hi=np.floor(tri.max(0)*64).astype(int)
        for x in range(lo[0],hi[0]+1):
            for y in range(lo[1],hi[1]+1):
                cell=grid.setdefault((x,y),[])
                for j in cell:pairs.add((j,i))
                cell.append(i)
    pairs=list(pairs);overlap=0
    for s in range(0,len(pairs),10000):
        ix=np.array(pairs[s:s+10000]);a=t[ix[:,0]];b=t[ix[:,1]]
        e=np.concatenate([np.roll(a,-1,1)-a,np.roll(b,-1,1)-b],1)
        ax=np.stack([-e[:,:,1],e[:,:,0]],2);ax/=np.maximum(np.linalg.norm(ax,axis=2,keepdims=True),1e-20)
        pa=np.einsum('nvc,nac->nva',a,ax);pb=np.einsum('nvc,nac->nva',b,ax)
        depth=np.minimum(pa.max(1),pb.max(1))-np.maximum(pa.min(1),pb.min(1))
        overlap+=int(np.all(depth>1e-9,1).sum())
    report[name]['overlapping_uv_triangles']=overlap
    assert overlap==0,(name,overlap)
images=[i for i in bpy.data.images if i.type=='IMAGE']
report['material_images']={i.name:list(i.size) for i in images}
assert len(images)==6 and all(list(i.size)==[2048,2048] for i in images)
data=(ROOT.parents[2]/'assets/models/doors/medical_hermetic_door/medical_hermetic_door.glb').read_bytes()
size=struct.unpack_from('<I',data,12)[0];g=json.loads(data[20:20+size])
report['glb_bytes']=len(data);report['glb_images']=len(g['images']);report['glb_materials']=[m['name'] for m in g['materials']]
assert len(g['images'])==6 and all('bufferView' in i for i in g['images'])
assert not g.get('cameras') and not g.get('animations')
for mesh in g['meshes']:
    for p in mesh['primitives']:
        if 'normalTexture' in g['materials'][p['material']]:assert 'TANGENT' in p['attributes']
report['validation_passed']=True
(ROOT/'realistic_validation.json').write_text(json.dumps(report,indent=2))
print('REALISTIC_VALIDATION_OK',json.dumps(report))

