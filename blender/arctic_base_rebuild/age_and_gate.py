"""Weathered coating and rebuilt portal hardware. Run after refine_materials.py."""
import bpy,bmesh,math,numpy as np
# Re-parameterise the scanned blue paint as worn pale coating; source feature positions stay aligned.
source=bpy.data.images.load(str(OUT/'pbr/blue_metal_color.jpg'),check_existing=True)
a=np.array(source.pixels[:],dtype=np.float32).reshape(source.size[1],source.size[0],4);luma=a[:,:,:3]@np.array([.2126,.7152,.0722]);chips=np.clip((luma-.28)/.22,0,1);value=.84-np.minimum(.26,np.abs(luma-.18)*.75)-chips*.15
pixels=np.ones_like(a);pixels[:,:,:3]=value[:,:,None];warm=np.clip(a[:,:,0]-a[:,:,2],0,1);pixels[:,:,0]+=warm*.05;pixels[:,:,1]+=warm*.015
image=bpy.data.images.new('Weathered_Pale_Coating',width=source.size[0],height=source.size[1]);image.pixels.foreach_set(pixels.ravel());image.filepath_raw=str(OUT/'weathered_pale_coating.png');image.file_format='PNG';image.save()
m=MATS[0];p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED');tex=m.node_tree.nodes.new('ShaderNodeTexImage');tex.image=image;m.node_tree.links.new(tex.outputs['Color'],p.inputs['Base Color'])
normal=next(n for n in m.node_tree.nodes if n.type=='NORMAL_MAP');normal.inputs['Strength'].default_value=.35
im=bpy.data.images.load(str(OUT/'pbr/blue_metal_normal.jpg'),check_existing=True);im.colorspace_settings.name='Non-Color';nt=m.node_tree.nodes.new('ShaderNodeTexImage');nt.image=im;m.node_tree.links.new(nt.outputs['Color'],normal.inputs['Color'])
# Remove only the previous plain canopy sheet, retaining all other equipment.
ob=bpy.data.objects['Roof_TechnicalEquipment'];bm=bmesh.new();bm.from_mesh(ob.data)
remove=[v for v in bm.verts if -40.46<=v.co.x<=-38.24 and -4.36<=v.co.y<=-1.69 and 3.54<=v.co.z<=3.73]
bmesh.ops.delete(bm,geom=remove,context='VERTS');bm.to_mesh(ob.data);bm.free();ob.data.update()
# Curved insulated canopy with folded fascia and enclosed side cheeks.
hood=Geo('Entrance_Weather_Hood')
for j in range(18):
 def point(t,v):return Vector((-40.75+2.5*t,3.62+.23*math.sin(math.pi*v)+.2*t,1.3+3.4*v))
 for i in range(3):
  P=[point(i/3,j/18),point((i+1)/3,j/18),point((i+1)/3,(j+1)/18),point(i/3,(j+1)/18)]
  hood.solid(P,.10,(0,1,0),2)
 a0=point(0,j/18);b0=point(0,(j+1)/18);hood.beam(a0-Vector((0,.05,0)),b0-Vector((0,.05,0)),.13,1)
for zz,side in [(1.45,-1),(4.55,1)]:
 hood.solid([(-38.35,2.95,zz),(-40.5,3.50,zz),(-38.35,3.80,zz)],.10,(0,0,side),0)
 for xx,yy in [(-38.5,3.1),(-39.1,3.42),(-40.3,3.56)]:hood.bolt((xx,yy,zz+side*.025),(0,0,side),.04)
# Motor/roller enclosure over the garage: rounded leading cover, removable end plates.
for j in range(14):
 a0=math.pi*j/14;b0=math.pi*(j+1)/14
 P=[(-39.28-.42*math.sin(a0),4.46+.42*math.cos(a0),-5.98),(-39.28-.42*math.sin(a0),4.46+.42*math.cos(a0),.98),(-39.28-.42*math.sin(b0),4.46+.42*math.cos(b0),.98),(-39.28-.42*math.sin(b0),4.46+.42*math.cos(b0),-5.98)]
 hood.solid(P,.055,(-1,0,0),2)
for zz in [-5.98,.98]:
 hood.box((-39.45,4.05,zz-.05,-38.55,4.90,zz+.05),1)
 for y in [4.15,4.8]:hood.bolt((-39.48,y,zz),(-1,0,0),.045)
OBJECTS.append(hood.object(.018))
# New insulated sectional leaf, kept in door-local coordinates for the existing lift controller.
gate=Geo('Garage_Insulated_Shutter')
gate.box((-2.78,.04,-.09,2.78,3.62,.09),3)
for j in range(8):
 y=.06+j*.44;gate.box((-2.76,y,-.16,2.76,y+.422,.14),0)
 gate.beam((-2.70,y+.055,-.185),(2.70,y+.055,-.185),.045,1)
 for x in [-2.60,-1.35,0,1.35,2.60]:
  gate.box((x-.075,y+.12,-.205,x+.075,y+.31,-.16),1)
  for yy in [y+.15,y+.28]:gate.bolt((x,yy,-.225),(0,0,-1),.021)
for x in [-1.85,1.85]:
 gate.beam((x-.16,.75,-.29),(x+.16,.75,-.29),.04,5)
 for xx in [x-.16,x+.16]:gate.beam((xx,.75,-.29),(xx,.75,-.17),.035,5)
gate.box((-2.78,.025,-.18,2.78,.09,.16),1)
gate_obj=gate.object(.012)
# Stable local vertex weather: base splash, streak variation and frost on exposed edges.
for ob in OBJECTS+[gate_obj]:
 if ob.type!='MESH':continue
 me=ob.data;me.update();uv=me.uv_layers.active
 if not uv:continue
 color=me.color_attributes.get('Weathering') or me.color_attributes.new(name='Weathering',type='FLOAT_COLOR',domain='CORNER');me.color_attributes.active_color=color
 for poly in me.polygons:
  axis=max(range(3),key=lambda k:abs(poly.normal[k]));axes=[k for k in range(3) if k!=axis]
  for li in poly.loop_indices:
   co=me.vertices[me.loops[li].vertex_index].co
   if poly.material_index==0:uv.data[li].uv=(co[axes[0]]*.4,co[axes[1]]*.4)
   # Broad tint variation stays subtle; ground-contact wear is stronger.
   field=.5+.3*math.sin(co.x*.87+co.y*.33)+.2*math.sin(co.y*1.77-co.x*.28)
   soil=max(0,1-max(0,co.z)/2.0)*(.18+.15*field)
   streak=(.5+.5*math.sin(co.x*5.9+co.y*3.7))**8*.05
   value=max(.52,1-soil-streak)
   if poly.material_index in [0,1,2]:color.data[li].color=(value*.98,value*.985,value,1)
   else:color.data[li].color=(1,1,1,1)
# Blender and glTF both multiply the active vertex wear by the source PBR color.
for idx in [0,1,2]:
 m=MATS[idx];p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
 vertex=m.node_tree.nodes.new('ShaderNodeVertexColor');vertex.layer_name='Weathering';mix=m.node_tree.nodes.new('ShaderNodeMixRGB');mix.blend_type='MULTIPLY';mix.inputs[0].default_value=1
 if p.inputs['Base Color'].is_linked:m.node_tree.links.new(p.inputs['Base Color'].links[0].from_socket,mix.inputs[1])
 else:mix.inputs[1].default_value=p.inputs['Base Color'].default_value
 m.node_tree.links.new(vertex.outputs['Color'],mix.inputs[2]);m.node_tree.links.new(mix.outputs['Color'],p.inputs['Base Color'])
# Leaf is a separate asset; do not export it at the base origin.
for o in bpy.context.scene.objects:o.select_set(False)
gate_obj.hide_set(False);gate_obj.select_set(True);bpy.context.view_layer.objects.active=gate_obj
bpy.ops.export_scene.gltf(filepath=str(OUT/'garage_shutter.glb'),export_format='GLB',use_selection=True,use_active_scene=True,export_vertex_color='ACTIVE',export_texcoords=True,export_normals=True,export_materials='EXPORT',export_apply=True)
gate_obj.hide_render=True;gate_obj.hide_set(True)
print('AGED COATING, NEW CANOPY AND GARAGE SHUTTER',flush=True)
