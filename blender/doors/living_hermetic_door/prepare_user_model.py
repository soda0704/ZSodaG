"""Package the user-authored door. Never writes the input .blend or builds geometry."""
import bpy,bmesh,json,math,hashlib,struct
from pathlib import Path
from mathutils import Vector,Matrix,kdtree
ROOT=Path(__file__).resolve().parent
SOURCE=ROOT/'living_hermetic_door.blend'
OUT=ROOT.parents[2]/'assets/models/doors/living_hermetic_door'
source_hash=hashlib.sha256(SOURCE.read_bytes()).hexdigest()
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene=bpy.context.scene
scene.unit_settings.system='METRIC'; scene.unit_settings.scale_length=1
def active(o):
    bpy.ops.object.select_all(action='DESELECT'); o.select_set(True); bpy.context.view_layer.objects.active=o
def snapshot(objects,evaluated=False):
    points=[]; faces=0; triangles=0
    dg=bpy.context.evaluated_depsgraph_get()
    for o in objects:
        e=o.evaluated_get(dg) if evaluated else o
        points += [e.matrix_world@v.co for v in e.data.vertices]
        faces+=len(e.data.polygons); e.data.calc_loop_triangles(); triangles+=len(e.data.loop_triangles)
    return points,faces,triangles
original=[o for o in scene.objects if o.type=='MESH']
before,face_count,tri_count=snapshot(original,True)
worlds={o.name:o.matrix_world.copy() for o in original}
old_parents={o.name:o.parent.name if o.parent else None for o in original}
# Materialize the already visible mirror/array output, without adding detail.
for o in original:
    if o.modifiers:
        active(o); bpy.ops.object.convert(target='MESH')
for o in original:
    o.parent=None; o.matrix_world=worlds[o.name]
    active(o); bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    o['source_object']=o.name

# Reuse the supplied 2K physical surface maps, rebuilding simple exportable nodes.
for mat in list(bpy.data.materials): bpy.data.materials.remove(mat)
materials={}
for name,col in [('M_Door_Frame',(.19,.225,.23)),('M_Door_Leaf',(.61,.635,.62)),('M_Door_Recess_Seal',(.065,.079,.076)),('M_Living_Accent',(.235,.355,.285))]:
    m=bpy.data.materials.new(name); m.use_nodes=True; m.diffuse_color=(*col,1)
    nt=m.node_tree; bs=nt.nodes.get('Principled BSDF')
    for suffix,noncolor in [('BaseColor',False),('ORM',True)]:
        path=OUT/'textures'/(name[2:]+'_'+suffix+'.png')
        im=bpy.data.images.load(str(path),check_existing=True); im.colorspace_settings.name='Non-Color' if noncolor else 'sRGB'; im.pack()
        tex=nt.nodes.new('ShaderNodeTexImage'); tex.image=im
        tex.location=(-600,220 if suffix=='BaseColor' else -60)
        if suffix=='BaseColor': nt.links.new(tex.outputs['Color'],bs.inputs['Base Color'])
        else:
            split=nt.nodes.new('ShaderNodeSeparateColor'); split.location=(-350,-40)
            nt.links.new(tex.outputs['Color'],split.inputs[0]); nt.links.new(split.outputs['Green'],bs.inputs['Roughness']); nt.links.new(split.outputs['Blue'],bs.inputs['Metallic'])
            group=bpy.data.node_groups.get('glTF Material Output')
            if not group:
                group=bpy.data.node_groups.new('glTF Material Output','ShaderNodeTree'); group.interface.new_socket(name='Occlusion',in_out='INPUT',socket_type='NodeSocketFloat')
            gn=nt.nodes.new('ShaderNodeGroup'); gn.node_tree=group; gn.location=(-100,-180); nt.links.new(split.outputs['Red'],gn.inputs['Occlusion'])
    tex=nt.nodes.new('ShaderNodeTexImage'); tex.image=bpy.data.images.load(str(OUT/'textures/LivingDoor_Normal.png'),check_existing=True)
    tex.image.colorspace_settings.name='Non-Color'; tex.image.pack(); tex.location=(-600,-340)
    normal=nt.nodes.new('ShaderNodeNormalMap'); normal.inputs['Strength'].default_value=.25; normal.location=(-300,-320)
    nt.links.new(tex.outputs['Color'],normal.inputs['Color']); nt.links.new(normal.outputs['Normal'],bs.inputs['Normal'])
    materials[name]=m
for name,col in [('M_Status_Red',(.65,.018,.008)),('M_Status_Green',(.08,.45,.18))]:
    m=bpy.data.materials.new(name); m.use_nodes=True; m.diffuse_color=(*col,1)
    bs=m.node_tree.nodes.get('Principled BSDF'); bs.inputs['Base Color'].default_value=(*col,1)
    bs.inputs['Emission Color'].default_value=(*col,1); bs.inputs['Emission Strength'].default_value=1.5; bs.inputs['Roughness'].default_value=.3
    materials[name]=m

def assign(o,names):
    o.data.materials.clear()
    for name in names: o.data.materials.append(materials[name])
    for p in o.data.polygons: p.material_index=0
for o in original:
    assign(o,['M_Door_Frame'])
    if o.name in ['Left','Right']:
        assign(o,['M_Door_Leaf','M_Door_Recess_Seal','M_Living_Accent','M_Door_Frame'])
        # Classify existing face zones only. No cuts, decals, bevels or new surfaces.
        for p in o.data.polygons:
            c=o.matrix_world@p.center
            yy=abs(c.y)
            if abs(yy-.03903)<.0002 and abs(p.normal.y)>.9: p.material_index=1
            if 1.284<c.z<1.345 and .0392<yy<.065 and abs(c.x-(-.590208 if o.name=='Left' else .600208))<.46: p.material_index=2
            if .09<c.z<.38 and yy>.062 and abs(c.x-( -.590208 if o.name=='Left' else .600208))<.54: p.material_index=3
    if o.name=='Lamps':
        assign(o,['M_Status_Red','M_Status_Green'])
        for p in o.data.polygons: p.material_index=1 if (o.matrix_world@p.center).z>1.4 else 0

def empty(name,loc,parent=None):
    o=bpy.data.objects.new(name,None); scene.collection.objects.link(o); o.location=loc
    o.empty_display_type='PLAIN_AXES'; o.empty_display_size=.10; o.parent=parent; return o
def parent_keep(o,parent):
    world=o.matrix_world.copy(); o.parent=parent; o.matrix_parent_inverse=Matrix.Identity(4)
    o.matrix_basis=parent.matrix_world.inverted()@world; bpy.context.view_layer.update()
def origin(o,p):
    scene.cursor.location=p; active(o); bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
root=empty('LivingHermeticDoor',(0,0,0))
root['source']='User-authored geometry'; root['units']='metres'; root['front_axis']='Blender -Y / Godot +Z'
frame=bpy.data.objects['Frame.001']; frame.name='Frame'; origin(frame,(0,0,0)); parent_keep(frame,root)
for old,new in [('Left','LeftLeaf'),('Right','RightLeaf')]:
    o=bpy.data.objects[old]
    points=[o.matrix_world@v.co for v in o.data.vertices]
    center=Vector(tuple((min(v[i] for v in points)+max(v[i] for v in points))/2 for i in range(3)))
    o.name=new; origin(o,center); parent_keep(o,root)
    o['closed_x_m']=o.location.x; o['open_x_m']=o.location.x+(-1.255 if new=='LeftLeaf' else 1.255)
    o['travel_m']=1.255; o['motion_axis']='local X'
    for child in original:
        if old_parents[child['source_object']]==old:
            suffix=child['source_object'].split('.')[-1]
            child.name=new+'_Fasteners_'+suffix; origin(child,center); parent_keep(child,o)
f=bpy.data.objects['Cylinder']; f.name='FrameFasteners'; origin(f,(0,0,0)); parent_keep(f,frame)

def split_sides(o,names):
    result=[]
    for side,name in [(-1,names[0]),(1,names[1])]:
        polys=[p for p in o.data.polygons if (o.matrix_world@p.center).y*side>0]
        ids=sorted({i for p in polys for i in p.vertices}); mapping={v:i for i,v in enumerate(ids)}
        me=bpy.data.meshes.new(name+'_Mesh')
        me.from_pydata([o.matrix_world@o.data.vertices[i].co for i in ids],[],[[mapping[i] for i in p.vertices] for p in polys])
        for mat in o.data.materials: me.materials.append(mat)
        for new,old in zip(me.polygons,polys): new.material_index=old.material_index; new.use_smooth=old.use_smooth
        ob=bpy.data.objects.new(name,me); scene.collection.objects.link(ob); ob['source_object']=o['source_object']; result.append(ob)
    bpy.data.objects.remove(o,do_unlink=True); return result
casings=split_sides(bpy.data.objects['Indicator'],('FrontStatusLamps','BackStatusLamps'))
lenses=split_sides(bpy.data.objects['Lamps'],('FrontStatusLenses','BackStatusLenses'))
for casing,lens in zip(casings,lenses): parent_keep(casing,root); parent_keep(lens,casing)
empty('Socket_FrontAccessPanel',(1.720,-.200,1.483),root)
back=empty('Socket_BackAccessPanel',(-1.720,.200,1.483),root); back.rotation_euler.z=math.pi
bpy.context.view_layer.update()
meshes=[o for o in scene.objects if o.type=='MESH']

# Unique UV islands at uniform world-space texel density. Keep authored polygons.
bpy.ops.object.select_all(action='DESELECT')
for o in meshes: o.select_set(True)
bpy.context.view_layer.objects.active=frame
for o in meshes:
    while o.data.uv_layers: o.data.uv_layers.remove(o.data.uv_layers[0])
    o.data.uv_layers.new(name='UVMap')
bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.smart_project(angle_limit=math.radians(30),island_margin=.003)
bpy.ops.uv.average_islands_scale(); bpy.ops.uv.pack_islands(rotate=True,margin=.003,shape_method='CONVEX')
bpy.ops.object.mode_set(mode='OBJECT')

after,new_faces,new_tris=snapshot(meshes)
assert len(before)==len(after),(len(before),len(after))
assert face_count==new_faces,(face_count,new_faces)
assert tri_count==new_tris,(tri_count,new_tris)
tree=kdtree.KDTree(len(before))
for i,p in enumerate(before): tree.insert(p,i)
tree.balance(); max_error=max(tree.find(p)[2] for p in after)
assert max_error<1e-5,max_error
report={'source_sha256':source_hash,'source_file_unchanged':True,'vertices_before':len(before),'vertices_after':len(after),'faces_before':face_count,'faces_after':new_faces,'triangle_count':new_tris,'max_world_vertex_deviation_m':max_error,'objects':{},'boundary_edges':0,'nonmanifold_junctions':0,'degenerate_faces':0}
for o in meshes:
    bm=bmesh.new(); bm.from_mesh(o.data)
    boundary=sum(e.is_boundary for e in bm.edges); junction=sum(len(e.link_faces)>2 for e in bm.edges); deg=sum(f.calc_area()<1e-12 for f in bm.faces)
    report['boundary_edges']+=boundary; report['nonmanifold_junctions']+=junction; report['degenerate_faces']+=deg; bm.free()
    report['objects'][o.name]={'parent':o.parent.name,'origin':list(o.location),'dimensions':list(o.dimensions),'boundary_edges':boundary,'rotation':list(o.rotation_euler),'scale':list(o.scale)}
    assert all(abs(v)<1e-5 for v in o.rotation_euler)
    assert all(abs(v-1)<1e-5 for v in o.scale)
report['notes']=['Source boundary edges retained; no holes filled and no bevels added.','Frame and both leaf bodies are closed.','Original polygons retained in Blender; GLB tessellates them.','Leaf origins use actual bounds; positions were not snapped to the earlier brief.','Indicator mirror/array realized; existing faces split into front/back groups.']
(ROOT/'prepared_validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
scene.cursor.location=(0,0,0)
active(root)
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            area.spaces.active.region_3d.view_distance=5.7; area.spaces.active.region_3d.view_location=(0,0,1.5)
            area.spaces.active.region_3d.view_rotation=(Vector((4,-7,3.5))-Vector((0,0,1.5))).to_track_quat('Z','Y')
            area.spaces.active.shading.type='MATERIAL'
# Remove orphan prototype data from the copy; all current scene data stays intact.
bpy.data.orphans_purge(do_recursive=True)
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'living_hermetic_door_prepared.blend'))
# Tessellate only the temporary export session for reliable tangent normals.
# The saved Blender copy above retains all user polygons.
for o in meshes:
    active(o); mod=o.modifiers.new('Export tessellation','TRIANGULATE')
    bpy.ops.object.modifier_apply(modifier=mod.name)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=str(OUT/'living_hermetic_door.glb'),export_format='GLB',use_selection=True,export_yup=True,export_animations=False,export_extras=True,export_cameras=False,export_lights=False,export_texcoords=True,export_normals=True,export_tangents=True,export_materials='EXPORT')
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest()==source_hash,'Input changed during packaging'

scene.render.engine='CYCLES'; scene.cycles.samples=32; scene.cycles.use_denoising=True
scene.render.resolution_x=1200; scene.render.resolution_y=1200; scene.render.resolution_percentage=100
scene.world.color=(.18,.18,.18); scene.view_settings.view_transform='AgX'
def aim(o): o.rotation_euler=(Vector((0,0,1.5))-o.location).to_track_quat('-Z','Y').to_euler()
for loc,power,size in [((0,-4,5.5),1100,5),((4,-1,2.5),700,3),((-4,1,4),950,3)]:
    bpy.ops.object.light_add(type='AREA',location=loc); o=bpy.context.object; o.data.energy=power; o.data.shape='DISK'; o.data.size=size; aim(o)
bpy.ops.object.camera_add(location=(4,-7,3.7)); cam=bpy.context.object; cam.data.type='ORTHO'; cam.data.ortho_scale=4.3; aim(cam); scene.camera=cam
scene.render.filepath=str(ROOT/'prepared_front.png'); bpy.ops.render.render(write_still=True)
cam.location=(-3.4,7,3.2); aim(cam)
for o in scene.objects:
    if o.type=='LIGHT': o.location.y=-o.location.y; aim(o)
scene.render.filepath=str(ROOT/'prepared_back.png'); bpy.ops.render.render(write_still=True)
print('USER_MODEL_PREPARED',new_tris,'triangles',max_error,'maximum vertex deviation')
