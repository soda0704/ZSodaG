"""Run with Blender --background --python tools/build_weapon_models.py.
Original low-poly prototype models, metric units. Blender +Y is muzzle forward.
"""
import bpy
import math
from mathutils import Vector
from pathlib import Path

OUT = Path(__file__).resolve().parents[1] / 'assets' / 'models' / 'weapons'
OUT.mkdir(parents=True, exist_ok=True)
(OUT / 'source').mkdir(exist_ok=True)

def material(name, color, metallic=0.0, roughness=0.45):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Metallic'].default_value = metallic
    bsdf.inputs['Roughness'].default_value = roughness
    return m

def box(name, pos, size, mat, angle=0, bevel=0.002):
    bpy.ops.mesh.primitive_cube_add(size=1, location=pos)
    ob = bpy.context.object
    ob.name = name
    ob.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    ob.rotation_euler.x = angle
    ob.data.materials.append(mat)
    if bevel:
        mod = ob.modifiers.new('Machined edges', 'BEVEL')
        mod.width = bevel
        mod.segments = 2
        ob.modifiers.new('Weighted normals', 'WEIGHTED_NORMAL')
    return ob

def barrel(name, pos, radius, length, mat):
    bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=radius, depth=length, location=pos, rotation=(math.pi/2, 0, 0))
    ob = bpy.context.object
    ob.name = name
    ob.data.materials.append(mat)
    return ob

def save(name):
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / 'source' / (name + '.blend')))
    bpy.ops.export_scene.gltf(filepath=str(OUT / (name + '.glb')), export_format='GLB', export_apply=True)
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 16
    scene.render.resolution_x = 512
    scene.render.resolution_y = 512
    scene.render.resolution_percentage = 100
    scene.world.color = (0.25, 0.25, 0.25)
    ground_mat = material('Photo surface', (.24, .22, .18), 0, .9)
    box('Photo surface', (0, .12, -.19), (3, 3, .02), ground_mat)
    bpy.ops.object.camera_add(location=(.48, -.55, .7))
    camera = bpy.context.object
    camera.rotation_euler = (Vector((0, .12 if name == 'm4a1' else .05, 0)) - camera.location).to_track_quat('-Z', 'Y').to_euler()
    camera.data.type = 'ORTHO'
    camera.data.ortho_scale = 1.1 if name == 'm4a1' else .48
    scene.camera = camera
    bpy.ops.object.light_add(type='AREA', location=(.2, -.3, 1.2))
    bpy.context.object.data.energy = 65
    bpy.context.object.data.shape = 'DISK'
    bpy.context.object.data.size = 1.5
    scene.render.image_settings.file_format = 'PNG'
    scene.render.filepath = str(OUT.parents[1] / 'ui' / 'journal_photos' / (name + '.png'))
    bpy.ops.render.render(write_still=True)

def clear():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)

clear()
steel = material('Parkerized steel', (0.085, 0.1, 0.115), 0.8)
poly = material('Textured black polymer', (0.035, 0.04, 0.045), 0.0, 0.75)
silver = material('Brushed stainless steel', (0.52, 0.57, 0.61), 0.9, 0.26)
dark = material('Recesses', (0.008, 0.009, 0.01))
wood = material('Walnut handle', (0.19, 0.065, 0.027), 0.0, 0.6)

box('Pistol_Frame', (0, .055, .025), (.034, .18, .034), poly)
box('Slide', (0, .066, .055), (.035, .20, .035), steel)
box('Grip', (0, -.017, -.03), (.031, .045, .095), poly, -.17)
box('Magazine', (0, -.009, -.075), (.031, .044, .008), steel)
barrel('Barrel', (0, .172, .055), .009, .022, steel)
barrel('Bore', (0, .184, .055), .0055, .001, dark)
box('Front_sight', (0, .148, .077), (.006, .009, .008), steel)
box('Rear_sight_L', (-.009, -.014, .077), (.006, .012, .008), steel)
box('Rear_sight_R', (.009, -.014, .077), (.006, .012, .008), steel)
box('Trigger', (0, .035, -.012), (.006, .007, .026), steel, -.2)
box('Guard_bottom', (0, .044, -.03), (.012, .064, .008), poly)
box('Guard_front', (0, .075, -.012), (.012, .009, .04), poly)
for i in range(6):
    for side in [-1, 1]:
        box('Slide_serration', (side*.018, -.013+i*.006, .055), (.001, .002, .025), dark, bevel=0)
box('Ejection_port', (.018, .082, .059), (.001, .035, .014), dark, bevel=0)
save('pistol')

clear()
box('Upper_receiver', (0, .08, .045), (.05, .235, .07), steel)
box('Lower_receiver', (0, .036, -.005), (.042, .145, .05), steel)
box('Pistol_grip', (0, -.009, -.071), (.032, .05, .115), poly, -.3)
box('Magazine', (0, .113, -.084), (.028, .071, .145), steel, .16)
for side in [-1, 1]:
    for i in range(3):
        box('Magazine_rib', (side*.0148, .096+i*.017, -.083), (.002, .005, .11), dark, .16)
barrel('Buffer_tube', (0, -.10, .048), .02, .16, steel)
box('Adjustable_stock', (0, -.195, .029), (.055, .14, .085), poly)
box('Stock_pad', (0, -.27, .004), (.06, .015, .13), poly)
box('Handguard', (0, .28, .047), (.057, .20, .073), poly)
barrel('Barrel', (0, .444, .052), .011, .16, steel)
barrel('Flash_hider', (0, .533, .052), .016, .034, steel)
barrel('Bore', (0, .551, .052), .008, .001, dark)
for i in range(22):
    box('Top_rail', (0, -.024+i*.018, .09), (.045, .008, .012), steel, bevel=.001)
for side in [-1, 1]:
    for i in range(7):
        box('Handguard_vent', (side*.029, .207+i*.024, .048), (.001, .012, .018), dark, bevel=0)
box('Front_sight', (0, .403, .094), (.012, .015, .07), steel)
box('Rear_sight', (0, -.013, .108), (.03, .012, .022), steel)
box('Ejection_port', (.026, .052, .053), (.002, .055, .019), dark)
box('Forward_assist', (.034, .004, .043), (.02, .021, .018), steel)
box('Trigger', (0, .03, -.049), (.008, .008, .028), steel, -.3)
box('Trigger_guard', (0, .033, -.065), (.015, .055, .008), steel)
save('m4a1')

clear()
box('Wood_handle', (0, -.045, 0), (.025, .12, .022), wood, bevel=.005)
box('Steel_bolster', (0, .018, 0), (.029, .014, .025), silver)
# A tapered chef's blade with a broad heel and pointed tip.
outline = [(-.023, .023), (.024, .023), (.023, .11), (.011, .19), (-.015, .24), (-.023, .16)]
verts = [(x, y, z) for z in [-.0015, .0015] for x, y in outline]
n = len(outline)
faces = [tuple(reversed(range(n))), tuple(range(n, n*2))]
faces += [(i, (i+1)%n, (i+1)%n+n, i+n) for i in range(n)]
mesh = bpy.data.meshes.new('Chef_blade_mesh')
mesh.from_pydata(verts, [], faces)
mesh.update()
blade = bpy.data.objects.new('Chef_blade', mesh)
bpy.context.collection.objects.link(blade)
blade.data.materials.append(silver)
for y in [-.075, -.038, 0]:
    bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=6, radius=.0035, location=(0, y, .012))
    bpy.context.object.name = 'Handle_rivet'
    bpy.context.object.data.materials.append(silver)
save('kitchen_knife')
print('WEAPON_MODELS: COMPLETE')
