import bpy,bmesh,json,hashlib
from pathlib import Path
from mathutils import Vector
R=Path(__file__).resolve().parent
src=R/'Medical_Hermetic_Door.blend'
bpy.ops.wm.open_mainfile(filepath=str(src))
def active(o):
 bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o
def points():
 return sorted(tuple(round(c,5) for c in o.matrix_world@v.co) for o in bpy.context.scene.objects if o.type=='MESH' for v in o.data.vertices)
before=points();faces=sum(len(o.data.polygons) for o in bpy.context.scene.objects if o.type=='MESH')
for o in list(bpy.context.scene.objects):
 if o.type=='MESH':active(o);bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
leaf=bpy.data.objects['stvorka']
assert all(not(min(leaf.data.vertices[i].co.x for i in p.vertices)<-0.001 and max(leaf.data.vertices[i].co.x for i in p.vertices)>0.001) for p in leaf.data.polygons),'Leaf faces cross middle'
for sign,name in [(-1,'LeftLeaf'),(1,'RightLeaf')]:
 o=leaf.copy();o.data=leaf.data.copy();bpy.context.collection.objects.link(o);o.name=name
 bm=bmesh.new();bm.from_mesh(o.data);bmesh.ops.delete(bm,geom=[v for v in bm.verts if v.co.x*sign<0],context='VERTS');bm.to_mesh(o.data);bm.free()
bpy.data.objects.remove(leaf,do_unlink=True)
mapping={'rama':'Frame','shurupi':'FrameFasteners','medical_board':'MedicalSign','Lights_rama':'StatusHousings_Upper','Lights_rama_bottom':'StatusHousings_Lower','Lights':'StatusLenses_Upper','Lights_bottom':'StatusLenses_Lower'}
for old,new in mapping.items():bpy.data.objects[old].name=new
root=bpy.data.objects.new('MedicalHermeticDoor',None);bpy.context.collection.objects.link(root)
for o in list(bpy.context.scene.objects):
 if o.type!='MESH':continue
 active(o)
 bpy.context.scene.cursor.location=(0,0,0) if 'Leaf' not in o.name else sum((o.matrix_world@v.co for v in o.data.vertices),Vector())/len(o.data.vertices)
 bpy.ops.object.origin_set(type='ORIGIN_CURSOR');world=o.matrix_world.copy();o.parent=root;o.matrix_world=world
 o.data.materials.clear()
 for name in ['M_Door_Leaf','M_Door_Recess_Seal','M_Living_Accent']:
  m=bpy.data.materials.get(name) or bpy.data.materials.new(name);o.data.materials.append(m)
 for p in o.data.polygons:
  z=(o.matrix_world@p.center).z
  p.material_index=2 if 'Leaf' in o.name and 2.55<z<2.90 else 0
 if 'Lenses' in o.name:
  m=bpy.data.materials.get('M_Status_Teal') or bpy.data.materials.new('M_Status_Teal');m.use_nodes=True
  bs=m.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(.04,.45,.3,1);bs.inputs['Emission Color'].default_value=(.04,.5,.3,1);bs.inputs['Emission Strength'].default_value=1.5
  o.data.materials.clear();o.data.materials.append(m)
 bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.uv.smart_project(angle_limit=.523599,island_margin=.003);bpy.ops.object.mode_set(mode='OBJECT')
assert before==points(),'World vertices changed'
assert faces==sum(len(o.data.polygons) for o in bpy.context.scene.objects if o.type=='MESH')
ng=bpy.data.node_groups.new('glTF Material Output','ShaderNodeTree');ng.interface.new_socket(name='Occlusion',in_out='INPUT',socket_type='NodeSocketFloat')
(R/'source_validation.json').write_text(json.dumps({'source_sha256':hashlib.sha256(src.read_bytes()).hexdigest(),'world_vertices_unchanged':True,'vertices':len(before),'polygons':faces},indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(R/'medical_prepared.blend'))
