"""Offline volumetric rock sculpt. No Python, voxels or CSG run in the game.

Requires numpy/scipy/scikit-image; see cave_environment.md. The native Godot
importer saves ArrayMesh and ConcavePolygonShape3D resources from this bake.
All chunks sample ONE world-space field on the same grid, including their
shared boundary vertices. Never decimate chunks independently (that opens seams).
"""
from pathlib import Path
import argparse
import json
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/.local/cave-author-deps'))
import numpy as np
from scipy.spatial import cKDTree
from scipy.ndimage import map_coordinates
from skimage.measure import marching_cubes
import fast_simplification

STEP = 0.3
CELLS = 64
TILE = STEP * CELLS
OUT = ROOT / 'tools/.local/cave-reference/volume_bake'
INPUT = ROOT / 'tools/authoring/cave_sculpt_layout.json'


def smooth(a, b, x):
    t = np.clip((x-a)/(b-a), 0, 1)
    return t*t*(3-2*t)


def waves(p, scale=1):
    x, y, z = (p.T * scale)
    return (np.sin(x*.73 + y*.41 + z*.26) * np.cos(z*.67-y*.37)
            + .55*np.sin(x*1.31-z*.87+y*.23)) / 1.55


class Sculpt:
    def __init__(self):
        data = json.loads(INPUT.read_text())
        route = np.array(data['route'], np.float64)
        # Extend the last passage through the outside rock face, with no end cap.
        tail = np.array([[x, -156, 2, route[-1, 3]+x-342]
                         for x in np.arange(342.25, 366, .25)])
        self.route = np.vstack([route, tail])
        self.total = route[-1, 3]
        self.tree = cKDTree(self.route[:, [0, 2]])
        self.tangent = np.gradient(self.route[:, [0, 2]], axis=0)
        self.grade = np.gradient(self.route[:, 1])/np.maximum(np.linalg.norm(self.tangent,axis=1),.001)
        self.tangent /= np.linalg.norm(self.tangent, axis=1)[:, None]
        self.heightmap = np.array(data['terrain_heights'], np.float64)
        self.terrain_origin = np.array(data['terrain_origin'])
        self.manifest = []
        # Distinct chambers and lower side grottos, rather than a repeated profile.
        self.rooms = [(109, 3.5, 2.1, 12), (298, 4.0, 3.1, 16),
                      (526, 3.0, 2.3, 12), (self.total-91, 6.0, 3.4, 16)]

    def parameters(self, p):
        _, idx = self.tree.query(p[:, [0, 2]], workers=4)
        center = self.route[idx, :3].copy()
        tangent = self.tangent[idx]
        projection=np.sum((p[:,[0,2]]-center[:,[0,2]])*tangent,axis=1)
        projection=np.clip(projection,-.125,.125)
        projection=np.maximum(projection,-self.route[idx,3])
        projection=np.minimum(projection,self.route[-1,3]-self.route[idx,3])
        center[:,0]+=tangent[:,0]*projection;center[:,2]+=tangent[:,1]*projection
        center[:,1]+=self.grade[idx]*projection
        d = self.route[idx, 3]+projection
        signed=(p[:, 0]-center[:, 0])*tangent[:, 1] - (p[:, 2]-center[:, 2])*tangent[:, 0]
        lateral=np.copysign(np.linalg.norm(p[:,[0,2]]-center[:,[0,2]],axis=1),signed)
        # A broad changing grade plus small eroded ribs: no perfectly flat strip.
        envelope = smooth(5, 15, d)*(1-smooth(self.total-8, self.total, d))
        floor = center[:, 1] + envelope*(.20*np.sin(d*.19)+.11*np.sin(d*.57)
                  + .045*np.sin(d*1.47)+.11*waves(p*.8))
        floor += envelope*(.085*lateral*np.sin(d*.11)
                           + np.maximum(np.abs(lateral)-.7, 0)**1.25*.10)
        native=map_coordinates(self.heightmap,[p[:,0]-self.terrain_origin[0],p[:,2]-self.terrain_origin[1]],order=1,mode='nearest')
        apron=smooth(self.total,self.total+8,d)
        floor=floor*(1-apron)+(native-.28)*apron
        width = 2.65 + .72*np.sin(d*.051) + .44*np.cos(d*.12)
        height = 3.9 + .70*np.sin(d*.073) + .50*np.cos(d*.031)
        for location, w, h, length in self.rooms:
            a = np.exp(-((d-location)/length)**2)
            width += w*a
            height += h*a
        height += .65*np.sin(d*.15)*np.tanh(lateral*.5)
        low = np.zeros_like(d)
        for location in [self.total*.24, self.total*.58]:
            low = np.maximum(low, np.exp(-((d-location)/3.8)**4))
        height = height*(1-low) + 1.46*low
        # Keep S turns compact enough to hide the mouth; asymmetric buttresses
        # belong to the same rock volume, there is no freestanding screen plane.
        end = smooth(self.total-78, self.total-63, d)
        width = width*(1-end) + (2.3+.32*np.sin(d*.28))*end
        height = height*(1-end) + (3.35+.28*np.sin(d*.22))*end
        # Natural bottom chamber receiving the cage.
        start = 1-smooth(4, 17, d)
        width = width*(1-start)+4.6*start
        height = height*(1-start)+6.0*start
        return d, center, lateral, floor, width, height, low

    def outer_height(self, p):
        x, y, z = p.T
        native = map_coordinates(self.heightmap, [x-self.terrain_origin[0], z-self.terrain_origin[1]], order=1, mode='nearest')
        # Thick rocky lip grows out of the terrain and overhangs the mouth.
        ell = 1-((x-332)/12)**2-((z-2)/10.0)**2
        brow = -164 + np.sqrt(np.maximum(ell, 0))*14
        brow = np.where(ell > 0, brow, -180)
        blend = smooth(315, 321, x)*(1-smooth(348, 354, x))*(1-smooth(17, 23, np.abs(z-2)))
        # At the bake edge the mesh is embedded BELOW native terrain. Inside,
        # full rock thickness covers every edge of the rectangular terrain hole.
        top = np.maximum(native + .8*blend-.6*(1-blend), brow)
        top += blend*(.28*waves(p*.7)+.1*waves(p*2))
        return top

    def field(self, p, want_snow=False):
        d, center, lateral, floor, width, height, low = self.parameters(p)
        x, y, z = p.T
        elevation = y-floor
        # Tilted bedrock shelves, fractures and asymmetric weathering at three
        # scales. The actual surface changes shape in XYZ, not only a texture.
        bedding = y*.95 + x*.09 + z*.12 + .24*waves(p*.35)
        ribs = .42*np.abs(np.sin(bedding*2.3)) + .21*np.abs(np.sin(bedding*4.7+.8))
        relief = .52*waves(p*.55) + .21*waves(p*1.8) + .10*waves(p*4.1) - ribs
        relief *= (1-low*.85)*smooth(.1, .9, elevation)
        # Shoulders/arches blend between wide eroded galleries and tilted clefts.
        q = np.clip(elevation/np.maximum(height, 1), 0, 1)
        arch = 1-.30*q*q + .12*np.sin(q*6.5+d*.044)
        tilt = .32*np.sin(d*.058) + .18*waves(p*.32)
        wall = width*arch - np.abs(lateral-tilt*(q-.3)) + relief
        roof = height-elevation + .25*waves(p*.8)*(1-low)
        air = np.minimum(np.minimum(wall, roof), elevation)
        # Integrated stalactites. They join the roof rather than ending as paper
        # fragments. Leave a generous central walking corridor unobstructed.
        period = 8.5
        cell = np.floor(d/period)
        local = d-(cell+.5)*period
        side = np.where(np.mod(cell, 2) == 0, 1, -1)
        offset = side*width*.66
        length = (.65+.25*np.sin(cell*2.17))*(1-low)
        tip = floor+height-length
        radius = .06+.40*np.clip((y-tip)/np.maximum(length, .1), 0, 1.8)
        stal = np.minimum(radius-np.hypot(local, lateral-offset), np.minimum(y-tip, floor+height+.7-y))
        air = np.minimum(air, -stal)
        # The vertical cage axis stays clear, but the shaft wall has changing
        # centre, lobes, substantial ledges and lateral cavities throughout.
        sy = y+162
        sx = x+33.5
        sz = z+21
        theta = np.arctan2(sz, sx)
        radius = 5.0 + .85*np.sin(y*.24+theta*2) + .65*np.sin(y*.51-theta*3)
        radius += 1.8*np.exp(-((y+119)/6)**2)*(1+.5*np.cos(theta-1.4))
        radius += .7*waves(p*.6) + .22*waves(p*2)
        # Fit irregular rock tightly around/behind the short square concrete
        # collar. Nothing crosses the cage or the level-five walking floor.
        topblend = smooth(-97, -93, y)
        square = np.maximum(np.abs(sx), np.abs(sz))
        radial = (radius-np.hypot(sx-.6*np.sin(y*.15),sz-.7*np.cos(y*.13)))*(1-topblend)+(3.12-square)*topblend
        shaft = np.minimum(radial, np.minimum(y+162, -89.8-y))
        # Remove only the ceiling inside the floor-five opening. It is an
        # intentional, bounded entrance, not an unsealed missing wall.
        shaft = np.where(y > -92.9, np.minimum(3.12-square, y+162), shaft)
        air = np.maximum(air, shaft)
        # Turn the mouth's inner wall AND external rock cap into one volume.
        # Its rear/top/side seam sits inside the terrain, including from above.
        portal = x>250
        outer = self.outer_height(p)
        air = np.where(portal, np.maximum(air, y-outer), air)
        # Snow only on the outside of the rock lip; cave scree stays rock.
        if want_snow:
            snow = portal & (np.abs(y-outer)<.45) & (x>320)
            return air, snow.astype(np.float32)
        return air

    def tiles(self):
        keys = set()
        for row in self.route[:-90:4]:
            base = np.floor(row[:3]/TILE).astype(int)
            for ix in [-1, 0, 1]:
                for iy in [0, 1]:
                    for iz in [-1, 0, 1]:
                        keys.add(tuple(base+[ix, iy, iz]))
        # Some cave floors are near a tile boundary.
        for row in self.route[::24]:
            base=np.floor((row[:3]-[0,2,0])/TILE).astype(int)
            for ix in [-1,0,1]:
                for iz in [-1,0,1]:keys.add(tuple(base+[ix,0,iz]))
        for y in np.arange(-167,-87,TILE*.5):
            for dx in [-8,8]:
                for dz in [-8,8]:keys.add(tuple(np.floor(np.array([-33.5+dx,y,-21+dz])/TILE).astype(int)))
        for x in np.arange(315,356,8):
            for z in np.arange(-21,27,8):
                for y in np.arange(-170,-131,8):keys.add(tuple(np.floor(np.array([x,y,z])/TILE).astype(int)))
        return sorted(keys)

    def bake(self, sample=False):
        OUT.mkdir(parents=True,exist_ok=True)
        keys=self.tiles()
        if sample:
            center=self.route[round(141*4),:3]
            keys=[k for k in keys if np.linalg.norm((np.array(k)+.5)*TILE-center)<28]
        axis=np.arange(CELLS+1,dtype=np.float64)*STEP
        grid=np.stack(np.meshgrid(axis,axis,axis,indexing='ij'),axis=-1).reshape(-1,3)
        start=time.time();triangles=0
        for number,key in enumerate(keys):
            origin=np.array(key)*TILE
            points=grid+origin
            field=self.field(points).reshape((CELLS+1,)*3).astype(np.float32)
            if field.min()>=0 or field.max()<=0:continue
            vertices,faces,normals,_=marching_cubes(field,0,spacing=(STEP,)*3,allow_degenerate=False)
            vertices=vertices.astype(np.float64)+origin
            # Remove only surfaces outside the authored mouth footprint and the
            # intentional shaft opening; not arbitrary faces of scan geometry.
            centroids=vertices[faces].mean(axis=1)
            keep=~((centroids[:,0]>354)|(centroids[:,1]>-90.02))
            faces=faces[keep]
            if not len(faces):continue
            # World-space finite differences yield matching normals on every
            # tile seam; skimage's one-sided gradients would show square seams.
            normals=[]
            for dimension in range(3):
                delta=np.zeros(3);delta[dimension]=.035
                normals.append((self.field(vertices+delta)-self.field(vertices-delta))/.07)
            normals=np.stack(normals,axis=1)
            normals/=np.maximum(np.linalg.norm(normals,axis=1)[:,None],1e-12)
            cross=np.cross(vertices[faces[:,1]]-vertices[faces[:,0]],vertices[faces[:,2]]-vertices[faces[:,0]])
            if np.median(np.sum(cross*normals[faces].mean(axis=1),axis=1))>0:faces=faces[:,[0,2,1]]
            _,snow=self.field(vertices,True)
            name='rock_%d_%d_%d'%key
            # 3 position + 3 normal + snow mask, little endian, then index triplets.
            payload=np.column_stack([vertices,normals,snow]).astype('<f4')
            (OUT/(name+'.vertices')).write_bytes(payload.tobytes())
            (OUT/(name+'.indices')).write_bytes(faces.astype('<i4').tobytes())
            self.manifest.append({'name':name,'vertices':len(vertices),'triangles':len(faces)})
            triangles+=len(faces)
            if number%12==0:print('SCULPT',number,'/',len(keys),'triangles',triangles,'elapsed',round(time.time()-start),flush=True)
        (OUT/'manifest.json').write_text(json.dumps({'step':STEP,'tiles':self.manifest,'triangles':triangles,'sample':sample},indent=2))
        print('BAKED',len(self.manifest),'tiles',triangles,'triangles',round(time.time()-start),'seconds',flush=True)
        if not sample:self.reduce_whole_surface()

    def reduce_whole_surface(self):
        """Weld and simplify the whole cave BEFORE dividing into render tiles.

        Thus adjacent tiles cannot choose different seam vertices or open cracks.
        Open shaft/terrain-embedded boundary vertices are explicitly preserved.
        """
        verts=[];faces=[];offset=0
        for tile in self.manifest:
            v=np.fromfile(OUT/(tile['name']+'.vertices'),dtype='<f4').reshape(-1,7)[:,:3]
            f=np.fromfile(OUT/(tile['name']+'.indices'),dtype='<i4').reshape(-1,3)
            verts.append(v);faces.append(f+offset);offset+=len(v)
        verts=np.vstack(verts);faces=np.vstack(faces)
        unique,remap=np.unique(np.round(verts,4),axis=0,return_inverse=True)
        parent=np.arange(len(unique))
        for a,b in cKDTree(unique).query_pairs(.00016,output_type='ndarray'):
            while parent[a]!=a:a=parent[a]
            while parent[b]!=b:b=parent[b]
            parent[max(a,b)]=min(a,b)
        for i in range(len(parent)):
            while parent[i]!=parent[parent[i]]:parent[i]=parent[parent[i]]
        faces=parent[remap[faces]]
        faces=faces[(faces[:,0]!=faces[:,1])&(faces[:,1]!=faces[:,2])&(faces[:,0]!=faces[:,2])]
        source_count=len(faces)
        verts,faces=fast_simplification.simplify(unique.astype(np.float64),faces.astype(np.int32),target_reduction=.60,agg=5,preserve_border=True)
        normals=[]
        for dim in range(3):
            delta=np.zeros(3);delta[dim]=.035
            normals.append((self.field(verts+delta)-self.field(verts-delta))/.07)
        normals=np.stack(normals,axis=1);normals/=np.maximum(np.linalg.norm(normals,axis=1)[:,None],1e-12)
        _,snow=self.field(verts,True)
        all_payload=np.column_stack([verts,normals,snow]).astype('<f4')
        keys=np.floor(verts[faces].mean(axis=1)/TILE).astype(int)
        distinct,tile_index=np.unique(keys,axis=0,return_inverse=True)
        self.manifest=[]
        for number,key in enumerate(distinct):
            selected=faces[tile_index==number]
            used,remap=np.unique(selected,return_inverse=True)
            name='rock_%d_%d_%d'%tuple(key)
            (OUT/(name+'.vertices')).write_bytes(all_payload[used].tobytes())
            (OUT/(name+'.indices')).write_bytes(remap.astype('<i4').tobytes())
            self.manifest.append({'name':name,'vertices':len(used),'triangles':len(selected)})
        (OUT/'manifest.json').write_text(json.dumps({'step':STEP,'tiles':self.manifest,'triangles':len(faces),'source_triangles':source_count,'sample':False},indent=2))
        print('GLOBAL_REDUCTION',source_count,'->',len(faces),'triangles',flush=True)


if __name__=='__main__':
    args=argparse.ArgumentParser();args.add_argument('--sample',action='store_true')
    Sculpt().bake(args.parse_args().sample)
