"""Blender offline extension of Duane's Mind's tower; original zip is preserved.
Run with Blender --background --python this_file -- [path_to_original_zip].
Only original meshes/materials are reused for the mast, ladder and service deck.
"""
import bpy, bmesh
from mathutils import Vector, Matrix
from pathlib import Path
import json, math, sys, zipfile, struct, re

ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path(sys.argv[sys.argv.index('--')+1]) if '--' in sys.argv else Path('E:/Downloads/radio_communications_tower.zip')
TEMP = ROOT / 'tools/.local/radio_tower/source'
TEMP.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(SOURCE) as archive:
    for entry in archive.infolist():
        target = (TEMP / entry.filename).resolve()
        if not target.is_relative_to(TEMP.resolve()): raise ValueError('Archive path outside source directory')
    archive.extractall(TEMP)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.import_scene.gltf(filepath=str(TEMP/'scene.gltf'))
originals = {}
for obj in list(bpy.context.scene.objects):
    if obj.type == 'MESH':
        obj.data = obj.data.copy()
        obj.data.transform(obj.matrix_world)
        obj.parent = None; obj.matrix_world = Matrix.Identity(4)
        originals[obj.name] = obj
for obj in list(bpy.context.scene.objects):
    if obj.type != 'MESH': bpy.data.objects.remove(obj, do_unlink=True)
def find(prefix):
    return next(o for name,o in originals.items() if name.startswith(prefix))
def empty(name, position=(0,0,0)):
    obj = bpy.data.objects.new(name,None); bpy.context.scene.collection.objects.link(obj)
    obj.location=position
    return obj
structure = empty('structure')
gate = empty('gate_hinge',(-4.1726,-.187,0))
ladder = empty('ladder_visual')
def copy(source,name,parent=structure):
    obj = bpy.data.objects.new(name,source.data.copy()); bpy.context.scene.collection.objects.link(obj)
    obj.parent=parent
    return obj
def bounds(obj):
    return Vector([min(v.co[i] for v in obj.data.vertices) for i in range(3)]),Vector([max(v.co[i] for v in obj.data.vertices) for i in range(3)])
def box_copy(source,name,center,size):
    if source.name.startswith('Tower1_SectionA1_Platform_'):
        # The source intermediate landing has its own ladder aperture. Four
        # stretched copies would add four unsafe holes to the service deck.
        mesh=bpy.data.meshes.new(name)
        vertices=[tuple(Vector(center)+Vector((sx*size[0]/2,sy*size[1]/2,sz*size[2]/2))) for sx,sy,sz in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]]
        mesh.from_pydata(vertices,[],[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)])
        mesh.materials.append(source.data.materials[0])
        uv=mesh.uv_layers.new()
        for loop in mesh.loops:
            point=mesh.vertices[loop.vertex_index].co
            uv.data[loop.index].uv=(point.x,point.y)
        obj=bpy.data.objects.new(name,mesh);bpy.context.scene.collection.objects.link(obj);obj.parent=structure
        return obj
    obj=copy(source,name); low,high=bounds(obj)
    for v in obj.data.vertices:
        v.co=Vector([(v.co[i]-low[i])/max(high[i]-low[i],.0001)*size[i]+center[i]-size[i]/2 for i in range(3)])
    return obj
def beam(name,a,b,radius=.045):
    # Reorient an original round fence post, preserving its source UV/material.
    source=find('pCylinder43_'); obj=copy(source,name); low,high=bounds(obj)
    mid=(low+high)/2; axis=Vector(b)-Vector(a); rotation=Vector((0,0,1)).rotation_difference(axis.normalized())
    for v in obj.data.vertices:
        point=v.co-mid
        point.x*=radius*2/(high.x-low.x); point.y*=radius*2/(high.y-low.y); point.z*=axis.length/(high.z-low.z)
        v.co=rotation@point+(Vector(a)+Vector(b))/2
    return obj
pitch=3.03849; base_z=3.9377; deck=base_z+16*pitch+.106
def width(z): return 1.5-(1.5-.62)*max(0,min(1,(z-base_z)/(deck+3-base_z)))
for name,source in originals.items():
    if name.startswith(('Tower1_Section','Tower1_Top','polySurface700_','polySurface701_','polySurface702_','polySurface703_')): continue
    obj=copy(source,'original_'+name.replace(':','_').lower())
    if name.startswith('Tower1_Base_'):
        for v in obj.data.vertices: v.co.x*=1.5; v.co.y*=1.5
    if name.startswith(('Electric_Box2_','Lever1_','lever2_','Lever3_')):
        for v in obj.data.vertices: v.co.x += 1.8
    if name.startswith(('polySurface749_','polySurface746_')):
        obj.parent=gate
        for v in obj.data.vertices: v.co-=gate.location
frame=find('Tower1_SectionA1_Tower1_')
for section in range(16):
    obj=copy(frame,'mast_section_%02d'%section)
    for v in obj.data.vertices:
        v.co.z += section*pitch
        factor=width(v.co.z); v.co.x*=factor; v.co.y*=factor
top=copy(find('Tower1_Top_Tower1_'),'original_crown')
for v in top.data.vertices:
    v.co.z += 16*pitch+base_z-13.0223026
    factor=width(v.co.z); v.co.x*=factor; v.co.y*=factor
# Original ladders alternate sides at platforms. Use a continuous fixed-width
# run instead, with original rungs/rails at their authored spacing.
for side in [-1,1]:
    obj=beam('ladder_rail_%s'%side,(side*.24,.32,.05),(side*.24,.32,deck+1.15),.022)
    obj.parent=ladder
for step in range(1,math.floor((deck+1.1)/.3)+1):
    obj=beam('ladder_rung_%03d'%step,(-.24,.32,step*.3),(.24,.32,step*.3),.016)
    obj.parent=ladder
platform=find('Tower1_SectionA1_Platform_')
# Clear opening around the climbing capsule. Four strips form a real ring deck.
for name,center,size in [('left',(-1.2,0,deck),(1.35,3.8,.09)),('right',(1.2,0,deck),(1.35,3.8,.09)),('front',(0,-1.2,deck),(1.05,1.4,.09)),('back',(0,1.2,deck),(1.05,1.4,.09))]:
    box_copy(platform,'service_deck_'+name,center,size)
for i,(x,y) in enumerate([(-1.88,-1.88),(-1.88,0),(-1.88,1.88),(0,1.88),(1.88,1.88),(1.88,0),(1.88,-1.88),(-.58,-1.88),(.58,-1.88)]):
    beam('guard_post_%02d'%i,(x,y,deck),(x,y,deck+1.15),.025)
for height in [.58,1.13]:
    z=deck+height
    for i,(a,b) in enumerate([((-1.88,-1.88,z),(-1.88,1.88,z)),((-1.88,1.88,z),(1.88,1.88,z)),((1.88,1.88,z),(1.88,-1.88,z)),((-1.88,-1.88,z),(-.58,-1.88,z)),((.58,-1.88,z),(1.88,-1.88,z))]): beam('guard_rail_%s_%d'%(height,i),a,b,.022)
for i,(x,y) in enumerate([(-1.85,-1.85),(-1.85,1.85),(1.85,-1.85),(1.85,1.85)]):
    beam('deck_brace_%d'%i,(x*.33,y*.33,deck-1.8),(x,y,deck-.08),.04)
# Service cabinet and replacement cartridge both derive from the original box.
cabinet=box_copy(find('Electic_Box1_'),'service_cabinet',(1.3,-1.1,deck+.65),(.42,.65,1.2))
module=box_copy(find('Electric_Box2_'),'installed_module',(1.04,-1.1,deck+.85),(.12,.36,.28))
module.parent=empty('module_mount')
for obj in originals.values(): bpy.data.objects.remove(obj,do_unlink=True)
# Cut the continuous ladder well through the source section's internal crosspieces.
# Outer legs, face bracing, original materials and section joints remain intact.
bpy.ops.mesh.primitive_cube_add(size=1, location=(0,-.05,28))
cutter=bpy.context.object; cutter.name='ladder_well_tool'; cutter.scale=(1.12,1.12,58)
bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
for obj in list(bpy.context.scene.objects):
    if not (obj.name.startswith(('mast_section_','original_crown','original_Tower1_Base'.lower())) and obj.type=='MESH'): continue
    bpy.context.view_layer.objects.active=obj
    mod=obj.modifiers.new('Ladder access clearance','BOOLEAN'); mod.operation='DIFFERENCE'; mod.solver='EXACT'; mod.object=cutter
    bpy.ops.object.modifier_apply(modifier=mod.name)
    # The source uses open beam surfaces. Remove artificial long cutter caps
    # rather than turning the hollow mast into four continuous metal walls.
    bm=bmesh.new(); bm.from_mesh(obj.data)
    caps=[]
    for face in bm.faces:
        if face.calc_area()<.03: continue
        if any(all(abs(v.co[axis]-plane)<.0001 for v in face.verts) for axis,plane in [(0,-.56),(0,.56),(1,-.61),(1,.51)]): caps.append(face)
    bmesh.ops.delete(bm,geom=caps,context='FACES')
    bm.to_mesh(obj.data); bm.free()
bpy.data.objects.remove(cutter,do_unlink=True)
# Lowercase exported names; preserve original material shading and packed maps.
for obj in bpy.context.scene.objects: obj.name=obj.name.lower().replace(' ','_').replace(':','_')
module_data=module.data.copy()
# Static authoring groups share their original materials. Merge them offline
# so hundreds of ladder rungs do not become hundreds of runtime draw calls.
for group in [structure,ladder,gate]:
    meshes=[obj for obj in group.children if obj.type=='MESH']
    if not meshes: continue
    bpy.ops.object.select_all(action='DESELECT')
    for obj in meshes: obj.select_set(True)
    bpy.context.view_layer.objects.active=meshes[0]
    bpy.ops.object.join()
    meshes[0].name=group.name+'_mesh'
for image in bpy.data.images:
    if image.source=='FILE': image.pack()
dest=ROOT/'assets/models/radio_tower'; dest.mkdir(parents=True,exist_ok=True)
source_dir=ROOT/'blender/exterior/radio_tower'; source_dir.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(source_dir/'radio_tower.blend'))
bpy.ops.export_scene.gltf(filepath=str(dest/'radio_tower.glb'),export_format='GLB',export_yup=True,export_cameras=False,export_lights=False)
(dest/'license.txt').write_bytes((TEMP/'license.txt').read_bytes())
(dest/'authoring.json').write_text(json.dumps({'height':deck+3.04,'deck_height':deck,'ladder_bottom':[0,.15,.05],'ladder_top':[0,deck+.15,.05],'top_exit':[0,deck+.06,1.25],'bottom_exit':[0,.12,1.3],'original_mast_height':16.1689,'sections':16,'source_archive':SOURCE.name},indent=2)+'\n')
# Small independent cartridge for the shared story pickup near the trial computer.
bpy.ops.object.select_all(action='DESELECT')
dup=bpy.data.objects.new('radio_module',module_data); bpy.context.scene.collection.objects.link(dup)
dup.select_set(True); dup.parent=None
for v in dup.data.vertices: v.co-=Vector((1.04,-1.1,deck+.85))
dup.name='radio_module'
bpy.ops.export_scene.gltf(filepath=str(dest/'radio_module.glb'),export_format='GLB',use_selection=True,export_yup=True,export_cameras=False,export_lights=False)
print('RADIO TOWER AUTHORED',deck+3.04,'m; service deck',deck)

# Godot extracts embedded image names to files: enforce repository naming there too.
for target in [dest/'radio_tower.glb', dest/'radio_module.glb']:
    raw=target.read_bytes(); size=struct.unpack_from('<I',raw,12)[0]
    document=json.loads(raw[20:20+size])
    for im in document.get('images',[]):
        im['name']=re.sub(r'(?<=[a-z0-9])(?=[A-Z])','_',im.get('name','texture')).lower().replace(' ','_')
    encoded=json.dumps(document,separators=(',',':')).encode(); encoded+=b' '*((-len(encoded))%4)
    rest=raw[20+size:]
    target.write_bytes(struct.pack('<III',0x46546c67,2,20+len(encoded)+len(rest))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+rest)
