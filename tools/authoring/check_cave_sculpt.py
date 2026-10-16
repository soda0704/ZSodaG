"""Validate welded mesh edges, including off-route surfaces hidden from a walkthrough."""
from pathlib import Path
import json
import sys
import numpy as np
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/.local/cave-author-deps'))
from scipy.ndimage import map_coordinates
from scipy.spatial import cKDTree
OUT=ROOT/'tools/.local/cave-reference/volume_bake'
manifest=json.loads((OUT/'manifest.json').read_text())
vertices=[];faces=[];offset=0
for tile in manifest['tiles']:
    v=np.fromfile(OUT/(tile['name']+'.vertices'),dtype='<f4').reshape(-1,7)[:,:3]
    f=np.fromfile(OUT/(tile['name']+'.indices'),dtype='<i4').reshape(-1,3)
    vertices.append(v);faces.append(f+offset);offset+=len(v)
vertices=np.vstack(vertices);faces=np.vstack(faces)
# Exact tile-boundary coordinates can differ by one float32 ULP at world X=350.
# Weld only coincident vertices, within 0.08 mm, before counting edge incidence.
unique,remap=np.unique(np.round(vertices,4),axis=0,return_inverse=True)
pairs=cKDTree(unique).query_pairs(.00016,output_type='ndarray')
parent=np.arange(len(unique))
for a,b in pairs:
    while parent[a]!=a:a=parent[a]
    while parent[b]!=b:b=parent[b]
    parent[max(a,b)]=min(a,b)
for i in range(len(parent)):
    while parent[i]!=parent[parent[i]]:parent[i]=parent[parent[i]]
faces=parent[remap[faces]]
faces=faces[(faces[:,0]!=faces[:,1])&(faces[:,1]!=faces[:,2])&(faces[:,0]!=faces[:,2])]
edges=np.concatenate([faces[:,[0,1]],faces[:,[1,2]],faces[:,[2,0]]]);edges.sort(axis=1)
edges,counts=np.unique(edges,axis=0,return_counts=True)
boundary=edges[counts==1];mid=unique[boundary].mean(axis=1)
data=json.loads((ROOT/'tools/authoring/cave_sculpt_layout.json').read_text())
h=map_coordinates(np.array(data['terrain_heights']),[mid[:,0]-data['terrain_origin'][0],mid[:,2]-data['terrain_origin'][1]],order=1,mode='nearest')
buried=(mid[:,0]>=250)&(mid[:,1]<h-.15)
shaft=(mid[:,1]>-90.5)&(np.abs(mid[:,0]+33.5)<3.3)&(np.abs(mid[:,2]+21)<3.3)
bad=mid[~(buried|shaft)]
report={'triangles':manifest['triangles'],'open_edges':len(boundary),'buried_portal_edges':int(buried.sum()),
        'intentional_shaft_rim_edges':int(shaft.sum()),'exposed_unexpected_edges':len(bad),
        'nonmanifold_edges':int((counts>2).sum()),'unexpected_edge_samples':bad[:30].tolist()}
(OUT/'topology_report.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report,indent=2))
sys.exit(1 if len(bad) else 0)
