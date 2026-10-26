"""Reproducible Blender source asset. Run with Blender --background --python this_file."""
import bpy, bmesh, math, json, os
import numpy as np
import sys
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parent
OUT = ROOT.parents[2] / 'assets/models/doors/living_hermetic_door'
TEX = OUT / 'textures'
OUT.mkdir(parents=True, exist_ok=True)
TEX.mkdir(exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for d in list(bpy.data.materials): bpy.data.materials.remove(d)
scene=bpy.context.scene
scene.unit_settings.system='METRIC'
scene.unit_settings.scale_length=1

# Texture maps contain surface variation only, never lighting or AO shadows.
N=2048
rng=np.random.default_rng(1847)
noise=rng.normal(0, 1, (N,N)).astype(np.float32)
coarse=rng.random((64,64)).astype(np.float32)
coarse=np.repeat(np.repeat(coarse,32,0),32,1)-.5
scratches=np.zeros((N,N), np.float32)
for i in range(480):
    x,y=rng.integers(8,N-90,2); length=int(rng.integers(4,66))
    for k in range(length):
        yy=y+k; xx=x+int(k*.15)
        scratches[yy,xx]=rng.uniform(.12,.45)

def save_image(name, rgb, noncolor=False):
    img=bpy.data.images.new(name,width=N,height=N,alpha=False)
    img.colorspace_settings.name='Non-Color' if noncolor else 'sRGB'
    arr=np.ones((N,N,4),np.float32); arr[:,:,:3]=np.clip(rgb,0,1)
    img.pixels.foreach_set(arr.ravel())
    img.filepath_raw=str(TEX/(name+'.png')); img.file_format='PNG'; img.save()
    return img

normal=np.zeros((N,N,3),np.float32)
normal[:,:,0]=.5+noise*.007; normal[:,:,1]=.5+np.roll(noise,1,0)*.007; normal[:,:,2]=1
normal_image=save_image('LivingDoor_Normal',normal,True)
specs=[('M_Door_Frame',(.19,.225,.23),.68,.42),
       ('M_Door_Leaf',(.61,.635,.62),.56,.36),
       ('M_Door_Recess_Seal',(.065,.079,.076),.04,.79),
       ('M_Living_Accent',(.235,.355,.285),.40,.49)]
materials={}
for name,color,metal,rough in specs:
    mat=bpy.data.materials.new(name); mat.use_nodes=True
    mat.diffuse_color=(*color,1)
    nt=mat.node_tree; bs=nt.nodes.get('Principled BSDF')
    base=np.array(color)[None,None,:]*(1+noise[:,:,None]*.012+coarse[:,:,None]*.022)
    base+=scratches[:,:,None]*(.038 if metal else .008)
    img=save_image(name.replace('M_','')+'_BaseColor',base)
    orm=np.ones((N,N,3),np.float32)
    orm[:,:,1]=rough+noise*.012+coarse*.018+scratches*.08
    orm[:,:,2]=metal
    oi=save_image(name.replace('M_','')+'_ORM',orm,True)
    tex=nt.nodes.new('ShaderNodeTexImage'); tex.image=img; tex.label='Base Color • 2048 px'; tex.location=(-600,240)
    nt.links.new(tex.outputs['Color'],bs.inputs['Base Color'])
    ot=nt.nodes.new('ShaderNodeTexImage'); ot.image=oi; ot.label='ORM • R: AO=1 / G: Roughness / B: Metallic'; ot.location=(-600,-50)
    sep=nt.nodes.new('ShaderNodeSeparateColor'); sep.location=(-350,-40)
    nt.links.new(ot.outputs['Color'],sep.inputs[0]); nt.links.new(sep.outputs['Green'],bs.inputs['Roughness']); nt.links.new(sep.outputs['Blue'],bs.inputs['Metallic'])
    ni=nt.nodes.new('ShaderNodeTexImage'); ni.image=normal_image; ni.location=(-600,-330)
    nm=nt.nodes.new('ShaderNodeNormalMap'); nm.location=(-330,-300); nm.inputs['Strength'].default_value=.25
    nt.links.new(ni.outputs['Color'],nm.inputs['Color']); nt.links.new(nm.outputs['Normal'],bs.inputs['Normal'])
    # glTF AO export convention.
    group=bpy.data.node_groups.get('glTF Material Output')
    if not group:
        group=bpy.data.node_groups.new('glTF Material Output','ShaderNodeTree')
        group.interface.new_socket(name='Occlusion',in_out='INPUT',socket_type='NodeSocketFloat')
    gn=nt.nodes.new('ShaderNodeGroup'); gn.node_tree=group; gn.location=(-100,-150)
    nt.links.new(sep.outputs['Red'],gn.inputs['Occlusion'])
    materials[name]=mat
for name,color in [('M_Status_Red',(.65,.018,.008)),('M_Status_Green',(.08,.45,.18))]:
    mat=bpy.data.materials.new(name); mat.use_nodes=True; mat.diffuse_color=(*color,1)
    bs=mat.node_tree.nodes.get('Principled BSDF')
    bs.inputs['Base Color'].default_value=(*color,1)
    bs.inputs['Roughness'].default_value=.3
    bs.inputs['Emission Color'].default_value=(*color,1)
    bs.inputs['Emission Strength'].default_value=1.5
    materials[name]=mat

def active(o):
    bpy.ops.object.select_all(action='DESELECT'); o.select_set(True); bpy.context.view_layer.objects.active=o
def box(name, loc, size, mat=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o=bpy.context.object; o.name=name; o.dimensions=size
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    if mat: o.data.materials.append(materials[mat])
    return o
def boolean(a,b,op):
    active(a); mod=a.modifiers.new('Fabricated solid','BOOLEAN'); mod.operation=op; mod.solver='EXACT'; mod.object=b
    bpy.ops.object.modifier_apply(modifier=mod.name); bpy.data.objects.remove(b,do_unlink=True)
def bevel(o,w=.004,segments=2):
    active(o); m=o.modifiers.new('Machined edge radii','BEVEL'); m.width=w; m.segments=segments
    bpy.ops.object.modifier_apply(modifier=m.name)
    for p in o.data.polygons: p.use_smooth=True
    m=o.modifiers.new('Area weighted normals','WEIGHTED_NORMAL'); m.keep_sharp=True; m.weight=50
    bpy.ops.object.modifier_apply(modifier=m.name)
def join(parts,name,origin=(0,0,0)):
    bpy.ops.object.select_all(action='DESELECT')
    for o in parts: o.select_set(True)
    bpy.context.view_layer.objects.active=parts[0]; bpy.ops.object.join()
    o=bpy.context.object; o.name=name
    scene.cursor.location=origin; bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    return o
def empty(name,loc=(0,0,0),parent=None):
    o=bpy.data.objects.new(name,None); scene.collection.objects.link(o); o.location=loc
    o.empty_display_type='PLAIN_AXES'; o.empty_display_size=.12; o.parent=parent
    return o
root=empty('LivingHermeticDoor')
root['asset_version']='1.0'; root['units']='metres'; root['front_axis']='-Y (Blender) / +Z (Godot)'
root['opening_width_m']=2.4; root['opening_height_m']=2.7

# One closed extruded U profile avoids coplanar post/header Boolean seams.
profile=[(-1.5,0),(-1.2,0),(-1.2,2.7),(1.2,2.7),(1.2,0),(1.5,0),(1.5,3),(-1.5,3)]
verts=[(x,y,z) for y in [-.15,.15] for x,z in profile]
faces=[tuple(range(7,-1,-1)),tuple(range(8,16))]
faces += [(i,(i+1)%8,(i+1)%8+8,i+8) for i in range(8)]
fm=bpy.data.meshes.new('Frame_Profile'); fm.from_pydata(verts,[],faces); fm.materials.append(materials['M_Door_Frame'])
frame=bpy.data.objects.new('Frame',fm); scene.collection.objects.link(frame)
bm=bmesh.new(); bm.from_mesh(fm); bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces)); bm.to_mesh(fm); bm.free()
# Shallow machined rebates on both faces, within the exact frame envelope.
for side in [-1,1]:
    for x in [-1.35,1.35]:
        boolean(frame,box('rebate',(x,side*.155,1.48),(.17,.018,2.68)),'DIFFERENCE')
bevel(frame,.006,3)
frame=join([frame],'Frame'); frame.parent=root

def bolt(loc,side=1,r=.012,depth=.005):
    bpy.ops.mesh.primitive_cylinder_add(vertices=6,radius=r,depth=depth,location=loc,rotation=(math.pi/2,0,0))
    o=bpy.context.object; bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    o.data.materials.append(materials['M_Door_Frame']); bevel(o,.0007,1)
    return o

# Fasteners sit on the recessed frame surface, not in the passage.
fp=[frame]
for side in [-1,1]:
    for x in [-1.35,1.35]:
        for z in [.13,.82,1.5,2.27,2.83]: fp.append(bolt((x,side*.1475, z)))
        for z in [.158,2.803]:
            bead=box('frame weld',(x,side*.1475,z),(.145,.003,.004),'M_Door_Frame'); bevel(bead,.001,2); fp.append(bead)
    for x in [-.96,-.48,0,.48,.96]: fp.append(bolt((x,side*.147,2.86),depth=.005))
frame=join(fp,'Frame'); frame.parent=root
for v in frame.data.vertices:
    v.co.x=max(-1.5,min(1.5,v.co.x)); v.co.y=max(-.15,min(.15,v.co.y)); v.co.z=max(0,min(3,v.co.z))

# Seals contained in the jambs: no threshold and no reduction of clear opening.
seal_parts=[]
for side in [-1,1]:
    for x in [-1.209,1.209]:
        o=box('jamb seal',(x,side*.086,1.35),(.014,.023,2.69),'M_Door_Recess_Seal'); bevel(o,.003,2); seal_parts.append(o)
    o=box('header seal',(0,side*.086,2.710),(2.39,.023,.016),'M_Door_Recess_Seal'); bevel(o,.003,2); seal_parts.append(o)
seals=join(seal_parts,'FrameSeals'); seals.parent=root

for name,cx in [('LeftLeaf',-.595),('RightLeaf',.595)]:
    leaf=box(name,(cx,0,1.35),(1.19,.14,2.68),'M_Door_Leaf')
    # Wide recessed panel field on each side; real geometry, not a dark decal.
    for side in [-1,1]:
        boolean(leaf,box('recess cutter',(cx,side*.066,1.50),(.956,.068,2.12)),'DIFFERENCE')
        boolean(leaf,box('kick seat',(cx,side*.071,.235),(1.039,.020,.27)),'DIFFERENCE')
    bevel(leaf,.004,3)
    parts=[leaf]
    for side in [-1,1]:
        # Thin dark insert and upper/lower reinforcing plates. All parts are closed.
        o=box('recess liner',(cx,side*.034,1.50),(.939,.0038,2.102),'M_Door_Recess_Seal'); bevel(o,.003,2); parts.append(o)
        for z,h in [(1.925,.97),(.905,.50)]:
            o=box('reinforcement',(cx,side*.051,z),(.839,.029,h),'M_Door_Leaf'); bevel(o,.009,3); parts.append(o)
        o=box('living stripe',(cx,side*.051,1.314),(.871,.028,.052),'M_Living_Accent'); bevel(o,.003,2); parts.append(o)
        # Lower impact protection has a functional mounting gap above the sill.
        o=box('kick plate',(cx,side*.071, .235),(1.024,.006,.255),'M_Door_Frame')
        # Keep the full leaf within its 140 mm thickness.
        o.location.y=side*.066; bevel(o,.003,2); parts.append(o)
        for dx in [-.375,.375]:
            for z in [1.49,2.35,.70,1.105]: parts.append(bolt((cx+dx,side*.067,z),r=.009,depth=.004))
    leaf=join(parts,name,(cx,0,1.35)); leaf.parent=root
    leaf['closed_x_m']=cx; leaf['open_x_m']= -1.85 if cx<0 else 1.85; leaf['travel_m']=1.255
    leaf['motion_axis']='local X'; leaf['animation_owner']='Godot'
    if cx<0: left=leaf

# Bridge seals overlap the central meeting line only on the front/back face.
for name,side in [('CenterSeal_Front',-1),('CenterSeal_Back',1)]:
    o=box(name,(0,side*.078,1.35),(.024,.014,2.654),'M_Door_Recess_Seal'); bevel(o,.003,3)
    world=o.matrix_world.copy(); o.parent=left; o.matrix_world=world

for side,label in [(-1,'Front'),(1,'Back')]:
    parts=[]
    for x in [-1.48,1.48]:
        for z in [.55,2.10]:
            o=box('indicator housing',(x,side*.185,z),(.12,.07,.24),'M_Door_Frame')
            # Real lens recess, no concealed doubled faces behind the emitter.
            boolean(o,box('lens seat',(x,side*.220,z),(.06,.03,.145)),'DIFFERENCE')
            bevel(o,.006,3); parts.append(o)
            lens=box('status lens',(x,side*.219,z),(.055,.025,.14),'M_Status_Green' if z>1 else 'M_Status_Red'); bevel(lens,.005,3); parts.append(lens)
    obj=join(parts,label+'StatusLamps'); obj.parent=root
    obj['control']='Swap M_Status_Red / M_Status_Green or use a material override in Godot.'
front=empty('Socket_FrontAccessPanel',(1.720,-.200,1.483),root)
back=empty('Socket_BackAccessPanel',(-1.720,.200,1.483),root); back.rotation_euler.z=math.pi

# Equal-scale unique UV islands across the whole asset, without mirrored overlap.
meshes=[o for o in scene.objects if o.type=='MESH']
for o in meshes:
    bm=bmesh.new(); bm.from_mesh(o.data)
    bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.000001)
    bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=.000001)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    bmesh.ops.triangulate(bm,faces=list(bm.faces),quad_method='BEAUTY',ngon_method='BEAUTY')
    bm.to_mesh(o.data); bm.free(); o.data.update()
    # Rebuild to discard obsolete custom loop normals after Boolean cleanup.
    old=o.data; clean=bpy.data.meshes.new(o.name+'_Mesh')
    clean.from_pydata([tuple(v.co) for v in old.vertices],[],[tuple(p.vertices) for p in old.polygons])
    for mat in old.materials: clean.materials.append(mat)
    for a,b in zip(clean.polygons,old.polygons): a.material_index=b.material_index; a.use_smooth=False
    o.data=clean; bpy.data.meshes.remove(old)
bpy.ops.object.select_all(action='DESELECT')
for o in meshes: o.select_set(True)
bpy.context.view_layer.objects.active=frame
bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.smart_project(angle_limit=math.radians(30),island_margin=.003,area_weight=0)
bpy.ops.uv.average_islands_scale()
bpy.ops.uv.pack_islands(rotate=True,margin=.002,shape_method='CONVEX')
bpy.ops.object.mode_set(mode='OBJECT')

sys.path.insert(0,str(ROOT))
import uv_quality
uv_quality.fix(meshes)

report={'units':'metres','objects':{},'triangle_count':0,'non_manifold_edges':0,'degenerate_faces':0}
for o in meshes:
    bm=bmesh.new(); bm.from_mesh(o.data)
    bad=sum(not e.is_manifold for e in bm.edges)
    deg=sum(f.calc_area()<1e-12 for f in bm.faces)
    bm.free(); o.data.calc_loop_triangles()
    tris=len(o.data.loop_triangles)
    report['triangle_count']+=tris; report['non_manifold_edges']+=bad; report['degenerate_faces']+=deg
    report['objects'][o.name]={'triangles':tris,'non_manifold_edges':bad,'dimensions':list(o.dimensions),'location':list(o.location),'scale':list(o.scale),'rotation':list(o.rotation_euler),'parent':o.parent.name if o.parent else None}
assert report['triangle_count']<=50000,report
assert report['non_manifold_edges']==0,report
assert report['degenerate_faces']==0,report
assert all(abs(a-b)<1e-5 for a,b in zip(frame.dimensions,(3,.3,3)))
for name in ['LeftLeaf','RightLeaf']:
    assert all(abs(a-b)<1e-5 for a,b in zip(bpy.data.objects[name].dimensions,(1.19,.14,2.68))),list(bpy.data.objects[name].dimensions)
report['notes']=['Frame envelope 3 x 0.30 x 3 m; lamps extend width to 3.08 m as specified.', 'Back socket has the explicitly requested 180 degree Z rotation.', 'No threshold, panel geometry, animation, collisions or wall.', 'Upper lenses green and lower lenses red are material previews only; Godot owns final state.']
(ROOT/'validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
for img in bpy.data.images:
    if img.source=='FILE' or img.filepath: img.pack()
materials['M_Status_Green'].use_fake_user=True
scene.cursor.location=(0,0,0)
bpy.ops.object.select_all(action='DESELECT'); root.select_set(True); bpy.context.view_layer.objects.active=root
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            area.spaces.active.region_3d.view_distance=5.7
            area.spaces.active.region_3d.view_location=(0,0,1.5)
            area.spaces.active.region_3d.view_rotation=(Vector((4,-7,3.5))-Vector((0,0,1.5))).to_track_quat('Z','Y')
            area.spaces.active.shading.type='MATERIAL'
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'living_hermetic_door.blend'))
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=str(OUT/'living_hermetic_door.glb'),export_format='GLB',use_selection=True,export_yup=True,export_animations=False,export_extras=True,export_cameras=False,export_lights=False,export_texcoords=True,export_normals=True,export_tangents=True,export_materials='EXPORT')

# Studio cameras and lights exist only in this temporary render session.
scene.render.engine='CYCLES'; scene.cycles.samples=40
scene.cycles.use_denoising=True
scene.render.resolution_x=1300; scene.render.resolution_y=1300; scene.render.resolution_percentage=100
scene.world.color=(.18,.18,.18)
scene.view_settings.view_transform='AgX'
scene.render.image_settings.file_format='PNG'
def aim(o,p): o.rotation_euler=(Vector(p)-o.location).to_track_quat('-Z','Y').to_euler()
for loc,power,size in [((0,-4,5.5),1100,5),((4,-1,2.5),700,3),((-4,1,4),950,3)]:
    bpy.ops.object.light_add(type='AREA',location=loc); light=bpy.context.object; light.data.energy=power; light.data.shape='DISK'; light.data.size=size; aim(light,(0,0,1.5))
bpy.ops.object.camera_add(location=(4,-7,3.7)); cam=bpy.context.object; cam.data.type='ORTHO'; cam.data.ortho_scale=4.3; aim(cam,(0,0,1.5)); scene.camera=cam
scene.render.filepath=str(ROOT/'preview_front.png'); bpy.ops.render.render(write_still=True)
cam.location=( -3.4,7,3.2); aim(cam,(0,0,1.5))
for o in scene.objects:
    if o.type=='LIGHT': o.location.y=-o.location.y; aim(o,(0,0,1.5))
scene.render.filepath=str(ROOT/'preview_back.png'); bpy.ops.render.render(write_still=True)
print('ASSET_COMPLETE',json.dumps(report))
