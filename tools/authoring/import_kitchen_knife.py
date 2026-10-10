import bpy,pathlib
from mathutils import Vector,Matrix
root=pathlib.Path(__file__).resolve().parents[2]; src=root/'assets/models/weapons/source/kitchen_knife_bornx'
bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(src/'scene.gltf'))
center=Vector((.016744,.106458,.022465));turn=Matrix.Diagonal((-1.,-1.,1.,1.));scale=.30/.329621
meshes=[o for o in bpy.data.objects if o.type=='MESH']
for o in meshes:
 points=[turn.to_3x3()@(o.matrix_world@v.co-center)*scale for v in o.data.vertices]
 o.parent=None;o.matrix_world=Matrix.Identity(4)
 for v,p in zip(o.data.vertices,points):v.co=p
 o.name={'Object_4':'Blade','Object_6':'Handle','Object_8':'Bolts','Object_10':'Bolster'}[o.name]
for o in list(bpy.data.objects):
 if o not in meshes:bpy.data.objects.remove(o,do_unlink=True)
bpy.ops.export_scene.gltf(filepath=str(root/'assets/models/weapons/kitchen_knife.glb'),export_format='GLB',export_apply=True)
print('REPLACED_KNIFE',len(meshes),scale)
