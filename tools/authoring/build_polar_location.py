"""Offline Blender composition. Exact terrain samples, grouped shores, no runtime generators."""
import bpy,bmesh,json,math,random
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/models/environment/polar_location';OUT.mkdir(parents=True,exist_ok=True)
d=json.loads((ROOT/'blender/polar_location/terrain_reference.json').read_text())
curve=json.loads((ROOT/'assets/environments/snow/smooth_stream_layout.json').read_text())
scene=bpy.data.scenes.new('NorthernLab_Polar_Location');bpy.context.window.scene=scene
manifest=[]
def ground(x,z):
    fx=(x-d['x0'])/d['step'];fz=(z-d['z0'])/d['step'];i=int(fx);j=int(fz);u=fx-i;v=fz-j;h=d['heights']
    vals=[h[j][i],h[j][i+1],h[j+1][i],h[j+1][i+1]]
    if any(a is None or not math.isfinite(a) for a in vals):raise ValueError(('terrain hole',x,z))
    return (vals[0]*(1-u)+vals[1]*u)*(1-v)+(vals[2]*(1-u)+vals[3]*u)*v
def obj(name,vertices,faces,masks,zone,smooth=False):
    mesh=bpy.data.meshes.new(name);mesh.from_pydata([(x,-z,y) for x,y,z in vertices],[],faces);mesh.update()
    ob=bpy.data.objects.new(name,mesh);scene.collection.objects.link(ob)
    col=mesh.color_attributes.new(name='SnowCover',type='FLOAT_COLOR',domain='POINT')
    for c,m in zip(col.data,masks):c.color=(m,m,m,1)
    for p in mesh.polygons:p.use_smooth=smooth
    ob['zone']=zone;ob['export_name']=name;return ob
def smooth(a,b,x):
    t=max(0,min(1,(x-a)/(b-a)));return t*t*(3-2*t)
def slab(name,x,z,length,depth,height,yaw,seed,zone):
    rng=random.Random(seed);bm=bmesh.new();floor=ground(x,z)
    for layer in range(3):
        for k in range(9):
            a=k*math.tau/9+rng.uniform(-.19,.19)
            xx=math.cos(a)*length*.5*rng.uniform(.78,1.1);zz=math.sin(a)*depth*.5*rng.uniform(.78,1.1)
            X=x+xx*math.cos(yaw)-zz*math.sin(yaw);Z=z+xx*math.sin(yaw)+zz*math.cos(yaw)
            if layer==0:Y=ground(X,Z)-.5
            else:
                X+=length*.11*math.sin(seed);Y=floor+height*(.28 if layer==1 else 1)+xx*.18+zz*.12+rng.uniform(-.09,.09)
            bm.verts.new((X,-Z,Y))
    r=bmesh.ops.convex_hull(bm,input=list(bm.verts));bmesh.ops.delete(bm,geom=r.get('geom_interior',[]),context='VERTS');bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    mesh=bpy.data.meshes.new(name);bm.to_mesh(mesh);bm.free();ob=bpy.data.objects.new(name,mesh);scene.collection.objects.link(ob)
    bpy.context.view_layer.objects.active=ob
    bevel=ob.modifiers.new('Fracture lip','BEVEL');bevel.width=.015;bevel.segments=1;bpy.ops.object.modifier_apply(modifier=bevel.name)
    col=mesh.color_attributes.new(name='SnowCover',type='FLOAT_COLOR',domain='POINT')
    for v,c in zip(ob.data.vertices,col.data):
        m=smooth(floor+height*.15,floor+height*.85,v.co.z)*.9;c.color=(m,m,m,1)
    ob['zone']=zone;ob['export_name']=name
def bank(name,points,zone):
    # points: shoreline x,z; outward horizontal normal; water level.
    verts=[];masks=[];faces=[];offsets=[-1.1,-.35,0,.55,1.5,3.0,5.5]
    for i,(x,z,nx,nz,water) in enumerate(points):
        end=smooth(0,3,i)*smooth(0,3,len(points)-1-i)
        top=max(water+.22,ground(x+nx*.55,z+nz*.55)+.08)
        for j,off in enumerate(offsets):
            X=x+nx*off;Z=z+nz*off;natural=ground(X,Z)
            y=[water-.55,water-.08,top-.12,top,natural+.08,natural+.04,natural-.10][j]
            y=(natural-.10)*(1-end)+y*end
            verts.append((X,y,Z));masks.append(smooth(1,5,j))
    for i in range(len(points)-1):
        for j in range(6):
            a=i*7+j;b=a+7
            faces.extend([(a,a+1,b),(a+1,b+1,b)])
    ob=obj(name,verts,faces,masks,zone,True)
    # Ensure a coherent upward orientation regardless of shoreline traversal direction.
    mesh=ob.data
    if sum(p.normal.z for p in mesh.polygons)<0:
        bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.reverse_faces(bm,faces=list(bm.faces));bm.to_mesh(mesh);bm.free()
def coast(cx,cz,rx,rz,level,angle):
    ux=math.cos(angle)*rx;uz=math.sin(angle)*rz
    # Find the actual water/terrain intersection instead of assuming an ellipse is the bank.
    last=.1
    for k in range(1,141):
        r=.1+k*.012
        if ground(cx+ux*r,cz+uz*r)>level+.10:
            lo=last;hi=r
            for _ in range(8):
                mid=(lo+hi)*.5
                if ground(cx+ux*mid,cz+uz*mid)>level+.10:hi=mid
                else:lo=mid
            r=(lo+hi)*.5;break
        last=r
    norm=math.hypot(ux,uz)
    return cx+ux*r,cz+uz*r,ux/norm,uz/norm,level
ponds=[('WestLagoon',-110,-105,40,29,-6,[2.7,4.7]),('EastPools',105,95,32,12,-2.76406994,[.35,2.35,4.5]),('WestPools',-215,90,17,31,-2.1364174,[2.1,4.4])]
for zone,cx,cz,rx,rz,level,angles in ponds:
    for g,angle in enumerate(angles):
        points=[coast(cx,cz,rx,rz,level,angle-.22+.44*i/28) for i in range(29)]
        bank(zone+'_Bank%02d'%g,points,zone)
        x,z,nx,nz,_=coast(cx,cz,rx,rz,level,angle)
        tangent=math.atan2(nz,nx)+math.pi/2
        for k,(along,out,L,W,H) in enumerate([(0,1.7,3.8,2,1.25),(-2.4,1.1,2.6,1.8,.65),(2.3,2.1,2.2,1.5,.8),(-3.4,2.6,.8,.65,.3),(3.3,1.0,.65,.5,.22)]):
            X=x+nx*out+math.cos(tangent)*along;Z=z+nz*out+math.sin(tangent)*along
            slab(zone+'_Group%d_%d'%(g,k),X,Z,L,W,H,tangent+.3*k,402+g*33+k+int(cx),zone)
        manifest.append({'zone':zone,'center':[x,z],'water':level})
# Two remaining stream bends; the accepted central authored bend is retained.
for g,z in enumerate([-153.0,-76.0]):
    for a,b in zip(curve,curve[1:]):
        if a[1]<=z<=b[1]:
            t=(z-a[1])/(b[1]-a[1]);cx=a[0]*(1-t)+b[0]*t;w=a[3]*(1-t)+b[3]*t;break
    side=1 if g==0 else -1;x=cx+side*(w+2.6)
    for k,(dx,dz,L,W,H) in enumerate([(0,0,3.4,1.9,1.1),(side*1.2,1.5,2.4,1.6,.7),(-side*.8,-1.9,1.4,1,.45),(side*1.5,-2.8,.7,.5,.25)]):
        slab('StreamShoulders_%d_%d'%(g,k),x+dx,z+dz,L,W,H,.5+k*.55,700+g*21+k,'StreamShoulders')

results=[]
for ob in scene.objects:
    mesh=ob.data;mesh.calc_loop_triangles();colors=mesh.color_attributes['SnowCover'];points=[];normals=[];masks=[]
    for tri in mesh.loop_triangles:
        for li in reversed(tri.loops):
            loop=mesh.loops[li];v=mesh.vertices[loop.vertex_index];n=mesh.corner_normals[li].vector
            points.append([v.co.x,v.co.z,-v.co.y]);normals.append([n.x,n.z,-n.y]);masks.append(colors.data[v.index].color[0])
    results.append({'name':ob['export_name'],'zone':ob['zone'],'vertices':points,'normals':normals,'snow':masks})
(OUT/'geometry.json').write_text(json.dumps(results,separators=(',',':')))
(OUT/'layout.json').write_text(json.dumps(manifest,indent=2))
path=ROOT/'blender/polar_location';path.mkdir(exist_ok=True,parents=True)
bpy.ops.wm.save_as_mainfile(filepath=str(path/'polar_location.blend'))
print('PASS location Blender composition',len(results),'meshes',sum(len(r['vertices'])//3 for r in results),'triangles')
