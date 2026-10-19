"""Offline authoring of the measured exterior only. Blender 5.1; Godot metres.
Run blender --background --python ... -- --pass 1 (silhouette) or --pass 3.
No gameplay scene, interior, collision or lighting source is modified here.
"""
import bpy,bmesh,math,json,sys
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2]
REF=json.loads((Path(__file__).parent/'reference_measurements.json').read_text())
args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
PASS=int(args[args.index('--pass')+1]) if '--pass' in args else 3
OUT=ROOT/'assets/models/architecture/arctic_base_exterior'
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
scene=bpy.context.scene;scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
MATS=[]
for name,color,metal,rough in [('M_BaseExterior',(.28,.36,.41,1),.25,.74),('M_Structure',(.075,.105,.13,1),.32,.72),('M_Roof',(.18,.24,.28,1),.28,.77),('M_ServiceRecess',(.035,.05,.065,1),.18,.85)]:
 m=bpy.data.materials.new(name);m.diffuse_color=color;m.use_nodes=True
 bs=next((n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED'),None)
 if bs is None:
  bs=m.node_tree.nodes.new('ShaderNodeBsdfPrincipled');out=m.node_tree.nodes.new('ShaderNodeOutputMaterial');m.node_tree.links.new(bs.outputs['BSDF'],out.inputs['Surface'])
 bs.inputs['Base Color'].default_value=color;bs.inputs['Metallic'].default_value=metal;bs.inputs['Roughness'].default_value=rough
 MATS.append(m)
def g(v):return (v[0],-v[2],v[1])
def mesh(name,verts,faces,materials=None):
 me=bpy.data.meshes.new(name);me.from_pydata([g(v) for v in verts],[],faces);me.update()
 ob=bpy.data.objects.new(name,me);scene.collection.objects.link(ob)
 for mat in MATS:me.materials.append(mat)
 if materials:
  for p,m in zip(me.polygons,materials):p.material_index=m
 bm=bmesh.new();bm.from_mesh(me);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free()
 return ob
def outline(bounds,offset=0,corner=.8):
 x0,z0,x1,z1=bounds;x0-=offset;z0-=offset;x1+=offset;z1+=offset
 c=min(corner,(x1-x0)*.22,(z1-z0)*.22)
 return [(x0+c,z0),(x1-c,z0),(x1,z0+c),(x1,z1-c),(x1-c,z1),(x0+c,z1),(x0,z1-c),(x0,z0+c)]
def loft(name,rings,mat=0,roof_from=99):
 n=len(rings[0][1]);verts=[(x,y,z) for y,pts in rings for x,z in pts];faces=[];mats=[]
 faces.append(tuple(reversed(range(n))));mats.append(mat)
 for j in range(len(rings)-1):
  for i in range(n):faces.append((j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i));mats.append(2 if j>=roof_from else mat)
 faces.append(tuple((len(rings)-1)*n+i for i in range(n)));mats.append(2 if len(rings)-2>=roof_from else mat)
 return mesh(name,verts,faces,mats)
def rect(x0,z0,x1,z1):return [(x0,z0),(x1,z0),(x1,z1),(x0,z1)]
def box(name,b,mat=1):
 x0,y0,z0,x1,y1,z1=b
 return loft(name,[(y0,rect(x0,z0,x1,z1)),(y1,rect(x0,z0,x1,z1))],mat)
def boolean(target,other,operation='UNION'):
 bpy.context.view_layer.objects.active=target
 mod=target.modifiers.new('Offline_'+operation,'BOOLEAN');mod.operation=operation;mod.solver='EXACT';mod.object=other
 bpy.ops.object.modifier_apply(modifier=mod.name);bpy.data.objects.remove(other,do_unlink=True)
def bevel(ob,width=.055,segments=2):
 bpy.context.view_layer.objects.active=ob
 mod=ob.modifiers.new('Silhouette bevel','BEVEL');mod.width=width;mod.segments=segments;mod.limit_method='ANGLE';mod.angle_limit=math.radians(25);mod.harden_normals=True
 bpy.ops.object.modifier_apply(modifier=mod.name)
def normals(ob):
 for p in ob.data.polygons:p.use_smooth=True
 if hasattr(ob.data,'set_sharp_from_angle'):ob.data.set_sharp_from_angle(angle=math.radians(38))
 bpy.context.view_layer.objects.active=ob
 mod=ob.modifiers.new('Weighted planar normals','WEIGHTED_NORMAL');mod.keep_sharp=True;mod.weight=40
 bpy.ops.object.modifier_apply(modifier=mod.name)
modules={};pieces=[];ridges={}
for name,data in REF['modules'].items():
 lo,hi=data['min'],data['max'];b=REF['exterior_design_bounds'][name];modules[name]=b
 if name=='hub':
  h=hi[1]+.62
  rings=[(-.42,outline(b,.55,1.0)),(.42,outline(b,.72,1.0)),(h,outline(b,.45,.9)),(h+.32,outline(b,.58,1.0)),(h+1.45,outline([b[0]+1.45,b[1]+1.45,b[2]-1.45,b[3]-1.45],0,1.4))]
  pieces.append(loft('MainEnvelope',rings,roof_from=3));ridges[name]=h+1.45
 else:
  eave=max(5.8,hi[1])+.65;ridge=eave+1.85
  if name in ['west','east']:
   mid=(b[1]+b[3])/2;top=[b[0]+2.3,mid-.85,b[2]-2.3,mid+.85]
  else:
   mid=(b[0]+b[2])/2;top=[mid-.85,b[1]+2.3,mid+.85,b[3]-2.3]
  rings=[(-.42,outline(b,.55,.65)),(.42,outline(b,.72,.65)),(5.5,outline(b,.42,.65)),(eave,outline(b,.52,.8)),(ridge,outline(top,0,.3))]
  pieces.append(loft(name.title()+'_ThermalHull',rings,roof_from=3));ridges[name]=ridge
# Sloping weather collars bridge the measured 2-m connectors, not the rooms.
for axis,side in [('x',-1),('x',1),('z',-1),('z',1)]:
 a0,a1=(7.65,10.55) if side>0 else (-10.55,-7.65)
 pts=rect(a0,-2.72,a1,2.72) if axis=='x' else rect(-2.72,a0,2.72,a1)
 verts=[(x,-.42,z) for x,z in pts]
 for x,z in pts:
  d=abs(x if axis=='x' else z);h=8.95-(d-7.65)/2.9*2.65;verts.append((x,h,z))
 pieces.append(mesh('WeatherCollar',verts,[(3,2,1,0),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7),(4,5,6,7)],[0,0,0,0,0,2]))
# Designed portal masses, whose apertures are cut AFTER joining all solids.
pieces.append(loft('GaragePortal',[( -.42,outline([-39.52,-6.28,-37.98,1.28],0,.16)),(4.65,outline([-39.52,-6.28,-37.98,1.28],0,.16)),(5.05,outline([-39.24,-6.04,-37.98,1.04],0,.12))],1))
pieces.append(loft('EntryPortal',[( -.42,outline([-39.9,1.67,-38.0,4.33],0,.13)),(3.65,outline([-39.9,1.67,-38.0,4.33],0,.13)),(4.05,outline([-39.65,1.85,-38.0,4.15],0,.10))],1))
main=pieces.pop(0)
for ob in pieces:boolean(main,ob)
if PASS>=2:
 # Continuous shared base/eave belts; all are welded to the main skin.
 for name,b in modules.items():
  if name=='hub':bands=[(.12,.62,.80),(8.58,9.05,.64)]
  else:bands=[(.12,.62,.80),(5.42,5.91,.63)]
  for y0,y1,o in bands:boolean(main,loft('StructuralBelt',[(y0,outline(b,o,.78)),(y1,outline(b,o,.78))],1))
 # Broad vertical buttresses follow the slanted wall instead of floating boxes.
 for name,b in modules.items():
  if name=='hub':continue
  along_x=name in ['west','east'];start,end=(b[0],b[2]) if along_x else (b[1],b[3])
  count=max(2,round((end-start-4)/5));stations=[start+2+(end-start-4)*i/count for i in range(count+1)]
  for station in stations:
   for side in [-1,1]:
    rings=[]
    for y,offset in [(.53,.72),(5.5,.42),(5.98,.49)]:
     edge=(b[3] if side>0 else b[1]) if along_x else (b[2] if side>0 else b[0])
     w=edge+side*offset
     pts=rect(station-.21,min(w-side*.07,w+side*.24),station+.21,max(w-side*.07,w+side*.24)) if along_x else rect(min(w-side*.07,w+side*.24),station-.21,max(w-side*.07,w+side*.24),station+.21)
     rings.append((y,pts))
    boolean(main,loft('WindLoadRib',rings,1))
 # Central hub corner guards define the octagonal crown at a larger scale.
 b=modules['hub']
 for idx in [1,3,5,7]:
  rings=[]
  for y,o in [(.58,.72),(8.92,.45)]:
   pts=outline(b,o,.9);a=Vector(pts[idx]);c=Vector(pts[(idx+1)%8]);direction=(c-a).normalized();normal=Vector((direction.y,-direction.x))
   rings.append((y,[tuple(a-normal*.06),tuple(c-normal*.06),tuple(c+normal*.28),tuple(a+normal*.28)]))
  boolean(main,loft('CornerArmor',rings,1))
# Precisely fitted splayed apertures: no alteration to existing gate/door leaves.
backplanes=[]
for name,p in REF['portals'].items():
 x0=p['front_x']-.55;x1=p['back_x'];zm,zp=p['z_min'],p['z_max'];m=p['front_margin'];top=p['top']
 verts=[(x0,-1,zm-m),(x0,-1,zp+m),(x0,top+.25,zp+m),(x0,top+.25,zm-m),(x1,-1,zm),(x1,-1,zp),(x1,top,zp),(x1,top,zm)]
 cutter=mesh('MeasuredPortalVoid',verts,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],[3]*6)
 boolean(main,cutter,'DIFFERENCE');backplanes.append(x1)
# Solar panels are moved onto the separate exterior rack by explicit user request.
# Remove generated rear caps and buried underside: no interior walls/ceiling meshes.
bm=bmesh.new();bm.from_mesh(main.data)
remove=[]
for f in bm.faces:
 coords=[v.co for v in f.verts]
 if all(abs(c.z+.42)<.0001 for c in coords):remove.append(f)
 elif any(all(abs(c.x-plane)<.0001 for c in coords) for plane in backplanes):remove.append(f)
bmesh.ops.delete(bm,geom=remove,context='FACES');bm.to_mesh(main.data);bm.free()
if PASS>=2:bevel(main,.045,2)
normals(main)
main.name='Base_ExteriorShell_Mesh';main.location=(0,0,0)
exports=[main]
if PASS>=3:
 tech=[]
 # Low weather hoods: few large shapes with large readable louvres, no greeble.
 for key,pos in [('north',(0,-18)),('south',(0,18)),('east',(23,0))]:
  x,z=pos;y=ridges[key]
  hood=loft('RoofAirHandling',[(y-.28,outline([x-1.25,z-1.9,x+1.25,z+1.9],0,.15)),(y+.70,outline([x-1.12,z-1.7,x+1.12,z+1.7],0,.22)),(y+.95,outline([x-.92,z-1.52,x+.92,z+1.52],0,.22))],1)
  bevel(hood,.06,2);normals(hood);tech.append(hood)
  # Visible framed louvre banks on the exposed sides of each hood.
  for side in [-1,1]:
   for k in range(4):
    blade=box('VentLouvre',[x+side*1.16-.025,y+.05+k*.14,z-1.25,x+side*1.16+.025,y+.105+k*.14,z+1.25],3);tech.append(blade)
 # Raised centre service crown, a low protected spine rather than a tower.
 b=modules['hub'];cx=(b[0]+b[2])/2;cz=(b[1]+b[3])/2;y=ridges['hub']
 crown=loft('CentralServiceCrown',[(y-.12,outline([cx-2.1,cz-4,cx+2.1,cz+4],0,.55)),(y+.60,outline([cx-1.85,cz-3.8,cx+1.85,cz+3.8],0,.55)),(y+.82,outline([cx-1.62,cz-3.6,cx+1.62,cz+3.6],0,.55))],1)
 bevel(crown,.06,2);normals(crown);tech.append(crown)
 # Broad sealed roof access plates on the ridge, with two protective raised ribs.
 for key,cx,cz in [('west',-24,0),('east',17,0)]:
  y=ridges[key];hatch=box('SealedServiceHatch',[cx-1.4,y+.015,cz-.63,cx+1.4,y+.15,cz+.63],1);bevel(hatch,.045,2);normals(hatch);tech.append(hatch)
 # A low freestanding rack by the backup-power room; the original panel meshes stay separate.
 for z in [4.30,6.14,7.98]:
  tech.append(box('SolarRackFoot',[-40.12,-.25,z-.10,-38.96,-.07,z+.10],1))
  tech.append(box('SolarRackPost',[-39.11,-.12,z-.055,-38.99,1.44,z+.055],1))
 for y in [.43,1.16]:tech.append(box('SolarRackCrossbeam',[-39.15,y-.055,4.30,-39.02,y+.055,7.98],1))
 # Join secondary equipment into one mesh per material set; no runtime creation.
 bpy.ops.object.select_all(action='DESELECT')
 for ob in tech:ob.select_set(True)
 bpy.context.view_layer.objects.active=tech[0];bpy.ops.object.join();equipment=bpy.context.object;equipment.name='Roof_TechnicalEquipment';exports.append(equipment)
# Only the three reduced selected variants are appended, never the source collection.
if PASS>=3:
 library=Path(__file__).parent/'Selected_Antennas_Reduced.blend'
 with bpy.data.libraries.load(str(library),link=False) as (src,dst):dst.objects=['Antenna_CentralLattice','Antenna_ScienceMast','Antenna_CrossArray']
 templates={o.name:o for o in dst.objects}
 placements=[('Antenna_CentralLattice',7.5,0,ridges['hub']+.81,0,0),('Antenna_ScienceMast',3.2,0,ridges['north']-.03,-23,0),('Antenna_CrossArray',2.6,-29,ridges['west']-.015,0,.4),('Antenna_CrossArray',2.3,27,ridges['east']-.015,0,-.5)]
 for idx,(key,height,x,y,z,turn) in enumerate(placements):
  ob=templates[key].copy();ob.data=templates[key].data.copy();scene.collection.objects.link(ob);ob.name=key+'_'+str(idx)
  for v in ob.data.vertices:
   a,b,c=v.co*height;v.co=(a*math.cos(turn)-b*math.sin(turn)+x,a*math.sin(turn)+b*math.cos(turn)-z,c+y)
  ob.location=(0,0,0);ob.rotation_euler=(0,0,0);ob.scale=(1,1,1)
  ob.data.materials.clear();ob.data.materials.append(MATS[0])
  for p in ob.data.polygons:p.material_index=0
  ob.data.validate(verbose=True,clean_customdata=True);ob.data.update();normals(ob);exports.append(ob)
 for ob in templates.values():bpy.data.objects.remove(ob,do_unlink=True)

# Hidden reference volumes remain editable in Blender and are never exported.
reference=bpy.data.collections.new('REFERENCE_existing_layout_NOT_EXPORTED');scene.collection.children.link(reference)
for key,b in REF['modules'].items():
 lo,hi=b['min'],b['max'];ob=box('REF_'+key,[lo[0],lo[1],lo[2],hi[0],hi[1],hi[2]],0)
 for col in list(ob.users_collection):col.objects.unlink(ob)
 reference.objects.link(ob);ob.display_type='WIRE';ob.hide_render=True;ob.hide_set(True)
reference.hide_render=True
bpy.ops.object.select_all(action='DESELECT')
for ob in exports:ob.select_set(True)
bpy.context.view_layer.objects.active=main
stats={'pass':PASS,'vertices':sum(len(o.data.vertices) for o in exports),'triangles':0,'objects':len(exports),'materials':len(MATS),'collisions':0,'texture_maps':0,'bounds_godot':{},'source_reference':'reference_measurements.json'}
for ob in exports:ob.data.calc_loop_triangles();stats['triangles']+=len(ob.data.loop_triangles)
OUT.mkdir(parents=True,exist_ok=True)
name='ArcticBase_ExteriorShell' if PASS==3 else 'ArcticBase_ExteriorShell_Pass1'
bpy.ops.export_scene.gltf(filepath=str(OUT/(name+'.glb')),export_format='GLB',use_selection=True,export_yup=True,export_apply=True,export_texcoords=False,export_normals=True,export_materials='EXPORT',export_cameras=False,export_lights=False)
blend=Path(__file__).parent/(name+'.blend');bpy.ops.wm.save_as_mainfile(filepath=str(blend))
(Path(__file__).parent/(name+'_stats.json')).write_text(json.dumps(stats,indent=2)+'\n')
print('EXTERIOR_STATS',json.dumps(stats))
