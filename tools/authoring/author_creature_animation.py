"""Run in Blender background. Preserve source GLBs; author reusable skeletal clips and game-ready GLBs."""
import bpy, math, json, re, struct
from pathlib import Path
from mathutils import Vector, Matrix, Euler
ROOT = Path(__file__).resolve().parents[2]

def bone(rig, name, head, tail, parent=None, deform=True):
 b=rig.data.edit_bones.new(name);b.head=head;b.tail=tail;b.use_deform=deform
 if parent:b.parent=rig.data.edit_bones[parent]
 return b

def target_matrix(rest, head, tail):
 direction=(tail-head).normalized();original=(rest.tail_local-rest.head_local).normalized()
 rotation=original.rotation_difference(direction).to_matrix()
 return Matrix.Translation(head)@(rotation@rest.matrix_local.to_3x3()).to_4x4()

def build(name, height, leg_specs, neck_specs, duration, stride, duty):
 bpy.ops.wm.read_factory_settings(use_empty=True)
 bpy.context.preferences.filepaths.save_version=0
 bpy.ops.import_scene.gltf(filepath=str(ROOT/'blender/monsters'/name/'source.glb'))
 meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
 correction=Matrix.Rotation(math.pi/2,4,'X')
 for obj in meshes:
  transform=correction@obj.matrix_world;obj.parent=None;obj.matrix_world=Matrix.Identity(4);obj.data.transform(transform)
 points=[v.co for o in meshes for v in o.data.vertices]
 lo=Vector(tuple(min(v[i] for v in points) for i in range(3)));hi=Vector(tuple(max(v[i] for v in points) for i in range(3)))
 factor=height/(hi.z-lo.z);center=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
 for obj in meshes:
  obj.name=name+'_mesh'
  for vertex in obj.data.vertices:vertex.co=(vertex.co-center)*factor
  obj.data.update()
 for obj in list(bpy.context.scene.objects):
  if obj.type!='MESH':bpy.data.objects.remove(obj,do_unlink=True)
 # The downloader's GLBs omit the supplied roughness/gloss images.
 # Restore those maps rather than making the creatures look like polished metal.
 texture_path=ROOT/'blender/monsters'/name/('roughness.png' if name=='head' else 'gloss.png')
 surface_image=bpy.data.images.load(str(texture_path));surface_image.colorspace_settings.name='Non-Color'
 if max(surface_image.size)>2048:
  ratio=2048/max(surface_image.size);surface_image.scale(int(surface_image.size[0]*ratio),int(surface_image.size[1]*ratio))
 if name!='head':
  import numpy as np
  pixels=np.empty(surface_image.size[0]*surface_image.size[1]*4,dtype=np.float32);surface_image.pixels.foreach_get(pixels)
  pixels=pixels.reshape((-1,4));pixels[:,:3]=1-pixels[:,:3];pixels[:,3]=1
  rough=bpy.data.images.new('roughness',width=surface_image.size[0],height=surface_image.size[1],is_data=True)
  rough.pixels.foreach_set(pixels.ravel());surface_image=rough
 for obj in meshes:
  for material in obj.data.materials:
   if not material or not material.use_nodes:continue
   shader=next((n for n in material.node_tree.nodes if n.type=='BSDF_PRINCIPLED'),None)
   if shader:
    texture=material.node_tree.nodes.new('ShaderNodeTexImage');texture.image=surface_image
    material.node_tree.links.new(texture.outputs['Color'],shader.inputs['Roughness'])
 # Embedded source images remain untouched in source.glb. Runtime maps are resized through Blender.
 for image in list(bpy.data.images):
  image.name=re.sub(r'[^a-z0-9]+','_',image.name.lower()).strip('_')
  if image.size[0]>2048 or image.size[1]>2048:
   scale=2048/max(image.size);image.scale(max(1,int(image.size[0]*scale)),max(1,int(image.size[1]*scale)))
  if image.has_data:image.pack()
 arm=bpy.data.armatures.new(name+'_skeleton');rig=bpy.data.objects.new('creature_rig',arm);bpy.context.scene.collection.objects.link(rig)
 bpy.context.view_layer.objects.active=rig;rig.select_set(True);bpy.ops.object.mode_set(mode='EDIT')
 bone(rig,'root',(0,0,0),(0,0,height*.15),deform=False)
 body_height=height*.54 if name=='head' else .88
 bone(rig,'body',(0,0,body_height),(0,0,body_height+height*.18),'root')
 parent='body'
 for n,h,t in neck_specs:bone(rig,n,h,t,parent);parent=n
 if name=='head':bone(rig,'jaw',(0,-.20,.47),(0,-.28,.25),'body')
 for label,hip,knee,foot in leg_specs:
  bone(rig,label+'_upper',hip,knee,'body')
  bone(rig,label+'_lower',knee,foot,label+'_upper')
  bone(rig,label+'_tip',foot,Vector(foot)+Vector((0,0,.025)),label+'_lower',False)
 bpy.ops.object.mode_set(mode='OBJECT')
 for mesh in meshes:
  bpy.ops.object.select_all(action='DESELECT');mesh.select_set(True);rig.select_set(True);bpy.context.view_layer.objects.active=rig
  bpy.ops.object.parent_set(type='ARMATURE_AUTO')
  if not mesh.vertex_groups:raise RuntimeError('Skinning failed: '+name)
  unweighted=[v for v in mesh.data.vertices if sum(g.weight for g in v.groups)<1e-6]
  deform=[b for b in rig.data.bones if b.use_deform]
  print('SKIN_FALLBACK',name,len(unweighted),'of',len(mesh.data.vertices),flush=True)
  for vertex in unweighted:
   distances=[]
   for b in deform:
    a=b.head_local;delta=b.tail_local-a
    t=max(0,min(1,(vertex.co-a).dot(delta)/max(delta.length_squared,1e-8)))
    distances.append(((vertex.co-(a+delta*t)).length,b.name))
   nearest=sorted(distances)[:2];weights=[1/max(d,.01)**4 for d,_ in nearest];total=sum(weights)
   for (_,label),weight in zip(nearest,weights):mesh.vertex_groups[label].add([vertex.index],weight/total,'REPLACE')
 scene=bpy.context.scene;scene.render.fps=60
 for action_name, seconds in [('idle_loop',2.0),('walk_loop',duration),('attack',.65)]:
  rig.animation_data_create();action=bpy.data.actions.new(action_name);rig.animation_data.action=action
  for p in rig.pose.bones:p.rotation_mode='QUATERNION'
  total=round(seconds*60)
  for frame in range(total+1):
   scene.frame_set(frame);t=frame/max(total,1);cycle=t*2*math.pi
   for p in rig.pose.bones:p.location=(0,0,0);p.rotation_quaternion=(1,0,0,0);p.scale=(1,1,1)
   body=rig.pose.bones['body']
   if action_name=='walk_loop':
    delta=Vector((math.sin(cycle)*(.012 if name=='head' else .025),0,(1-math.cos(cycle*2))*(.008 if name=='head' else .018)))
    lean=.035*math.sin(cycle) if name=='head' else .055*math.sin(cycle)
   elif action_name=='attack':
    strike=-.18*math.sin(math.pi*t/.55) if t<.55 else (min(1,(t-.55)/.45)**2*(3-2*min(1,(t-.55)/.45)))
    delta=Vector((0,-strike*(.06 if name=='head' else .16),strike*.035));lean=strike*.16
   else:delta=Vector((0,0,math.sin(cycle)*.006));lean=math.sin(cycle)*.008
   body.location=body.bone.matrix_local.to_3x3().inverted()@delta;body.rotation_quaternion=Euler((lean,0,.02*math.sin(cycle) if action_name=='walk_loop' else 0)).to_quaternion()
   if name=='head':rig.pose.bones['jaw'].rotation_quaternion=Euler((math.sin(cycle)*.025 if action_name!='attack' else math.sin(math.pi*t)*.22,0,0)).to_quaternion()
   else:
    for index,(n,_h,_tail) in enumerate(neck_specs):rig.pose.bones[n].rotation_quaternion=Euler((math.sin(cycle+index*.7)*(.045 if action_name=='walk_loop' else .012),0,math.sin(cycle-index*.45)*.035 if action_name=='walk_loop' else 0)).to_quaternion()
   bpy.context.view_layer.update()
   body_delta=body.matrix@body.bone.matrix_local.inverted()
   solutions=[]
   for index,(label,rest_hip,rest_knee,rest_foot) in enumerate(leg_specs):
    hip=body_delta@Vector(rest_hip);rest_knee=Vector(rest_knee);foot=Vector(rest_foot)
    if action_name=='walk_loop':
     offset=([0,.5,.5,0][index] if name=='head' else index/3)
     phase=(t+offset)%1
     if phase<duty:foot.y+=stride*(phase/duty-.5)
     else:
      swing=(phase-duty)/(1-duty);foot.y+=stride*(.5-swing);foot.z+=math.sin(math.pi*swing)*(.11 if name=='head' else .18)
    length1=(rest_knee-Vector(rest_hip)).length;length2=(Vector(rest_foot)-rest_knee).length
    aim=foot-hip;distance=min(max(aim.length,abs(length1-length2)+.001),length1+length2-.001);direction=aim.normalized();foot=hip+direction*distance
    along=(length1**2-length2**2+distance**2)/(2*distance);lift=math.sqrt(max(0,length1**2-along**2))
    pole=(body_delta@rest_knee)-hip;pole=(pole-direction*pole.dot(direction)).normalized()
    if pole.length<.01:pole=Vector((1,0,0))
    knee=hip+direction*along+pole*lift
    rig.pose.bones[label+'_upper'].matrix=target_matrix(rig.data.bones[label+'_upper'],hip,knee)
    bpy.context.view_layer.update()
    rig.pose.bones[label+'_lower'].matrix=target_matrix(rig.data.bones[label+'_lower'],knee,foot)
    bpy.context.view_layer.update()
   for p in rig.pose.bones:
    if p.name.endswith('_tip') or p.name=='root':continue
    p.keyframe_insert(data_path='location',frame=frame,group=p.name);p.keyframe_insert(data_path='rotation_quaternion',frame=frame,group=p.name)
  track=rig.animation_data.nla_tracks.new();track.name=action_name;strip=track.strips.new(action_name,0,action);strip.name=action_name
  rig.animation_data.action=None
 scene.frame_start=0;scene.frame_end=round(duration*60)
 rig.animation_data.action=None;scene.frame_set(0)
 for p in rig.pose.bones:p.location=(0,0,0);p.rotation_quaternion=(1,0,0,0)
 bpy.context.view_layer.update()
 source=ROOT/'blender/monsters'/name/(name+'.blend');bpy.ops.wm.save_as_mainfile(filepath=str(source))
 bpy.ops.object.select_all(action='DESELECT');rig.select_set(True)
 for obj in meshes:obj.select_set(True)
 destination=ROOT/'assets/monsters'/name/(name+'.glb')
 bpy.ops.export_scene.gltf(filepath=str(destination),export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='NLA_TRACKS',export_frame_range=False,export_force_sampling=True,export_def_bones=False,export_yup=True,export_tangents=True)
 # Normalize embedded image names too: Godot extracts them as files. The
 # exporter can synthesize a combined ORM name containing a hyphen.
 raw=destination.read_bytes();json_size=struct.unpack_from('<I',raw,12)[0]
 document=json.loads(raw[20:20+json_size])
 for index,image in enumerate(document.get('images',[])):
  image['name']=re.sub(r'[^a-z0-9]+','_',image.get('name','texture_'+str(index)).lower()).strip('_')
 encoded=json.dumps(document,separators=(',',':'),ensure_ascii=True).encode('utf-8');encoded+=b' '*((-len(encoded))%4)
 tail=raw[20+json_size:];destination.write_bytes(struct.pack('<III',0x46546c67,2,20+len(encoded)+len(tail))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+tail)
 (ROOT/'blender/monsters'/name/'animation_info.json').write_text(json.dumps({'height':height,'walk_duration':round(duration*60)/60,'stride':stride,'stance_fraction':duty,'reference_speed':stride/(duty*(round(duration*60)/60)),'bones':[b.name for b in rig.data.bones]},indent=2))
 print('AUTHORED',name,'REF_SPEED',stride/(duty*(round(duration*60)/60)),'BYTES',destination.stat().st_size,flush=True)

build('head',1.05,[
 ('front_left',(-.15,-.23,.48),(-.29,-.31,.30),(-.24,-.39,.025)),
 ('front_right',(.15,-.23,.48),(.29,-.31,.30),(.24,-.39,.025)),
 ('back_left',(-.19,.04,.50),(-.30,.31,.43),(-.22,.32,.025)),
 ('back_right',(.19,.04,.50),(.30,.31,.43),(.22,.32,.025))],[],.28,.38,.60)
build('involuntary_evolution',2.35,[
 ('left',(-.25,-.15,.88),(-.86,-.63,.52),(-.94,-.70,.025)),
 ('right',(.24,-.02,.88),(.88,-.08,.55),(.95,-.08,.025)),
 ('back',(-.12,.12,.82),(-.44,.49,.48),(-.34,.50,.025))],[
 ('neck_1',(0,0,1.02),(.20,-.02,1.25)),
 ('neck_2',(.20,-.02,1.25),(.49,0,1.53)),
 ('neck_3',(.49,0,1.53),(.15,-.39,1.88)),
 ('skull',(.15,-.39,1.88),(.14,-.43,2.21))],.90,.65,.70)
