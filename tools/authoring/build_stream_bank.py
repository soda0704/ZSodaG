"""Blender authoring: one terrain-conforming stream bend. No region writes."""
import bpy, bmesh, json, math, random
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/models/environment/stream_bend'
OUT.mkdir(parents=True, exist_ok=True)
ground = json.loads((ROOT/'blender/stream_bend/terrain_reference.json').read_text())
curve = json.loads((ROOT/'assets/environments/snow/smooth_stream_layout.json').read_text())
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)

def sample(x,z):
    fx=(x-ground['x0'])/ground['step']; fz=(z-ground['z0'])/ground['step']
    ix=int(fx); iz=int(fz); u=fx-ix; v=fz-iz; h=ground['heights']
    return (h[iz][ix]*(1-u)+h[iz][ix+1]*u)*(1-v)+(h[iz+1][ix]*(1-u)+h[iz+1][ix+1]*u)*v

def river(z):
    for a,b in zip(curve,curve[1:]):
        if z<=b[1]:
            t=max(0,min(1,(z-a[1])/(b[1]-a[1])))
            return tuple(a[i]*(1-t)+b[i]*t for i in (0,2,3))
    raise ValueError(z)

def smooth(a,b,x):
    t=max(0,min(1,(x-a)/(b-a))); return t*t*(3-2*t)

def mesh_object(name, verts, faces, coats, smooth_faces=False):
    # Godot xyz -> Blender xyz; common world origin keeps placement exact.
    mesh=bpy.data.meshes.new(name)
    mesh.from_pydata([(x,-z,y) for x,y,z in verts],[],faces); mesh.update()
    ob=bpy.data.objects.new(name,mesh); bpy.context.collection.objects.link(ob)
    color=mesh.color_attributes.new(name='SnowCover',type='FLOAT_COLOR',domain='POINT')
    for c,value in zip(color.data,coats): c.color=(value,value,value,1)
    for p in mesh.polygons: p.use_smooth=smooth_faces
    return ob

# A continuous, irregular cross-section, not repeated standalone blocks.
sections=81; rings=9; vertices=[]; coats=[]; faces=[]
for i in range(sections):
    z=-137+29*i/(sections-1); cx,water,width=river(z)
    end=smooth(0,3,z+137)*smooth(0,3,-108-z)
    notch=.16*math.sin(z*1.71)+.08*math.sin(z*4.13)
    offsets=[1.55,1.67,1.91,2.12,2.55,3.35,4.9,7.0,9.0]
    for j,off in enumerate(offsets):
        x=cx-width-off-notch*(1-j/8)
        natural=sample(x,z)
        top=max(water+.65,sample(cx-width-2.55,z)+.10)
        if j==0: shaped=water-.38
        elif j==1: shaped=water+.03+.04*math.sin(z*3)
        elif j==2: shaped=top-.32
        elif j==3: shaped=top-.12+.04*math.sin(z*2.9)
        elif j==4: shaped=top
        else: shaped=natural+.16*math.sin(math.pi*(j-4)/4)
        y=(natural-.07)*(1-end)+shaped*end
        if j==8: y=natural-.09
        vertices.append((x,y,z))
        coats.append((smooth(2,6,j)*end+(1-end)))
for i in range(sections-1):
    for j in range(rings-1):
        a=i*rings+j; b=a+rings
        # CCW in Blender after coordinate conversion.
        faces.extend([(a,a+1,b),(a+1,b+1,b)])
bank=mesh_object('LayeredWestBank',vertices,faces,coats,True)

# Clustered broken slabs: broad bedding, slanted fracture faces, chipped edges.
placements=[(-132.0,3.6,3.4,2.1,.48,.3),(-130.7,5.7,1.2,.9,.32,-.5),
            (-123.0,3.9,3.3,1.75,1.35,-.18),(-121.4,5.0,2.1,1.2,.85,.7),
            (-119.8,3.1,.85,.7,.24,-.4),(-113.8,4.4,2.8,1.6,.72,.42),
            (-123.8,4.8,1.8,1.4,.64,.9),(-132.8,4.5,1.7,1.4,.36,-.5),
            (-114.7,4.9,1.6,1.3,.44,-.65),(-121.9,2.9,.48,.4,.19,.4),
            (-125.3,4.1,.7,.55,.28,-.7),(-131.7,2.9,.6,.5,.22,.5)]
for idx,(z,off,length,depth,height,angle) in enumerate(placements):
    cx,water,width=river(z); x=cx-width-off
    rng=random.Random(9182+idx)
    bm=bmesh.new()
    for layer in range(3):
        for k in range(9):
            a=math.tau*k/9+rng.uniform(-.22,.22)
            xx=math.cos(a)*length*.5*rng.uniform(.8,1.12)
            zz=math.sin(a)*depth*.5*rng.uniform(.85,1.1)
            X=x+xx*math.cos(angle)-zz*math.sin(angle)
            Z=z+xx*math.sin(angle)+zz*math.cos(angle)
            if layer==0:Y=sample(X,Z)-.36
            elif layer==1:Y=sample(x,z)+height*.35+rng.uniform(-.12,.08)
            else:
                # Different bedding angles and broken upper outlines, not upright prisms.
                X+=length*.16*math.sin(idx*2.1);Z+=depth*.12*math.cos(idx)
                Y=sample(x,z)+height+xx*(.15+idx%3*.16)+zz*.12+rng.uniform(-.12,.10)
            bm.verts.new((X,-Z,Y))
    result=bmesh.ops.convex_hull(bm,input=list(bm.verts))
    bmesh.ops.delete(bm,geom=result.get('geom_interior',[]),context='VERTS')
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    mesh=bpy.data.meshes.new('BrokenSlab%02d'%idx);bm.to_mesh(mesh);bm.free()
    ob=bpy.data.objects.new(mesh.name,mesh);bpy.context.collection.objects.link(ob)
    bpy.context.view_layer.objects.active=ob
    bevel=ob.modifiers.new('Chipped fracture bevel','BEVEL');bevel.width=.018;bevel.segments=2
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    color=ob.data.color_attributes.new(name='SnowCover',type='FLOAT_COLOR',domain='POINT')
    for v,c in zip(ob.data.vertices,color.data):
        snow=smooth(sample(x,z)+height*.3,sample(x,z)+height*.85,v.co.z)*.88
        c.color=(snow,snow,snow,1)

# Portable triangles retain Blender normals and snow masks, imported as ArrayMesh.
result=[]
for ob in bpy.context.scene.objects:
    if ob.type!='MESH': continue
    mesh=ob.data; mesh.calc_loop_triangles(); colors=mesh.color_attributes['SnowCover']
    points=[]; normals=[]; masks=[]
    for tri in mesh.loop_triangles:
        for li in reversed(tri.loops):
            loop=mesh.loops[li]; v=mesh.vertices[loop.vertex_index]
            n=mesh.corner_normals[li].vector
            points.append([v.co.x,v.co.z,-v.co.y]); normals.append([n.x,n.z,-n.y])
            masks.append(colors.data[v.index].color[0])
    result.append({'name':ob.name.split('.')[0],'vertices':points,'normals':normals,'snow':masks})
(OUT/'geometry.json').write_text(json.dumps(result,separators=(',',':')))
blend_dir=ROOT/'blender/stream_bend'; blend_dir.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(blend_dir/'stream_bend_refined.blend'))
print('PASS authored Blender stream bend:',len(result),'meshes;',sum(len(m['vertices'])//3 for m in result),'triangles')
