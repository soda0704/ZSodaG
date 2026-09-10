import bpy, numpy as np

def overlaps(meshes):
    refs=[]; triangles=[]
    for o in meshes:
        uv=o.data.uv_layers.active.data
        for p in o.data.polygons:
            refs.append((o,p.index)); triangles.append([tuple(uv[i].uv) for i in p.loop_indices])
    triangles=np.asarray(triangles,dtype=np.float64); grid={}; pairs=set()
    for i,t in enumerate(triangles):
        low=np.floor(t.min(0)*128).astype(int); high=np.floor(t.max(0)*128).astype(int)
        for x in range(low[0],high[0]+1):
            for y in range(low[1],high[1]+1):
                cell=grid.setdefault((x,y),[])
                for j in cell: pairs.add((j,i))
                cell.append(i)
    pairs=list(pairs); bad=set()
    for start in range(0,len(pairs),20000):
        idx=np.asarray(pairs[start:start+20000]); a=triangles[idx[:,0]]; b=triangles[idx[:,1]]
        edges=np.concatenate((np.roll(a,-1,axis=1)-a,np.roll(b,-1,axis=1)-b),axis=1)
        axes=np.stack((-edges[:,:,1],edges[:,:,0]),axis=-1)
        axes/=np.maximum(np.linalg.norm(axes,axis=2,keepdims=True),1e-20)
        pa=np.einsum('nvc,nac->nva',a,axes); pb=np.einsum('nvc,nac->nva',b,axes)
        depth=np.minimum(pa.max(1),pb.max(1))-np.maximum(pa.min(1),pb.min(1))
        for pair in idx[np.all(depth>1e-9,axis=1)]: bad.update(pair)
    return [refs[i] for i in sorted(bad)]

def fix(meshes):
    for attempt in range(4):
        bad=overlaps(meshes)
        if not bad: return
        print('UV: isolate',len(bad),'small folded facets, iteration',attempt)
        for i,(o,index) in enumerate(bad):
            p=o.data.polygons[index]; uv=o.data.uv_layers.active.data
            a,b,c=[o.data.vertices[j].co for j in p.vertices]
            ab=b-a; ac=c-a; offset=10+i*5
            coords=[(offset,10),(offset+ab.length,10),(offset+ac.dot(ab.normalized()),10+ab.cross(ac).length/ab.length)]
            for loop,coord in zip(p.loop_indices,coords): uv[loop].uv=coord
        bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
        bpy.ops.uv.select_all(action='SELECT'); bpy.ops.uv.average_islands_scale()
        bpy.ops.uv.pack_islands(rotate=True,margin=.002,shape_method='CONVEX')
        bpy.ops.object.mode_set(mode='OBJECT')
    assert not overlaps(meshes),'UV repair did not converge'
