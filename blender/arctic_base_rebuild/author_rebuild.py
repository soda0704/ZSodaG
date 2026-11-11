"""Measured modular exterior, built from scratch. Execute in Blender; finish() exports.
Godot metres are mapped to Blender (x,-z,y). Old envelope assets remain intact.
"""
import bpy,bmesh,math,json,random
from pathlib import Path
from mathutils import Vector,Matrix
import numpy as np
ROOT=Path(r'D:/Github/ZSodaG');OUT=ROOT/'assets/models/architecture/arctic_base_rebuild'
REF=json.loads((ROOT/'blender/arctic_base_exterior_shell/reference_measurements.json').read_text())
rng=random.Random(10626);GROUPS={};OBJECTS=[]
def g(p):return Vector((p[0],-p[2],p[1]))
def material(name,c,m,r):
 a=bpy.data.materials.new(name);a.use_nodes=True;a.diffuse_color=(*c,1);p=next(n for n in a.node_tree.nodes if n.type=='BSDF_PRINCIPLED');p.inputs['Base Color'].default_value=(*c,1);p.inputs['Metallic'].default_value=m;p.inputs['Roughness'].default_value=r;return a
class Geo:
 def __init__(self,name):self.name=name;self.v=[];self.f=[];self.m=[];GROUPS[name]=self
 def solid(self,pts,depth,normal,mi):
  pts=[Vector(p) for p in pts];v=pts+[p-Vector(normal)*depth for p in pts];i=len(self.v);self.v+=v;n=len(pts)
  faces=[tuple(range(n)),tuple(reversed(range(n,2*n)))]+[(j,(j+1)%n,(j+1)%n+n,j+n) for j in range(n)]
  self.f += [tuple(i+k for k in f) for f in faces];self.m += [mi]*len(faces)
 def face(self,pts,mi):
  i=len(self.v);self.v += [Vector(p) for p in pts];self.f.append(tuple(range(i,len(self.v))));self.m.append(mi)
 def box(self,b,mi):
  x,y,z,X,Y,Z=b;self.solid([(x,Y,z),(X,Y,z),(X,Y,Z),(x,Y,Z)],Y-y,(0,1,0),mi)
 def beam(self,a,b,w,mi):
  a,b=Vector(a),Vector(b);d=(b-a).normalized();u=d.cross(Vector((0,1,0)))
  if u.length<.01:u=d.cross(Vector((1,0,0)))
  u.normalize();v=d.cross(u);self.solid([b+(u*s+v*t)*w*.5 for s,t in [(-1,-1),(1,-1),(1,1),(-1,1)]],(b-a).length,d,mi)
 def bolt(self,p,n,r=.026):
  n=Vector(n).normalized();u=n.cross(Vector((0,1,0)))
  if u.length<.01:u=n.cross(Vector((1,0,0)))
  u.normalize();v=n.cross(u);self.solid([Vector(p)+r*(u*math.cos(k*math.tau/6)+v*math.sin(k*math.tau/6)) for k in range(6)],.025,n,5)
 def object(self,radius=0):
  me=bpy.data.meshes.new(self.name);me.from_pydata([g(v) for v in self.v],[],self.f);me.update();ob=bpy.data.objects.new(self.name,me);bpy.context.scene.collection.objects.link(ob)
  for m in MATS:me.materials.append(m)
  for p,mi in zip(me.polygons,self.m):p.material_index=mi
  bm=bmesh.new();bm.from_mesh(me);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));
  if self.name=='Arched_Roof_Surface':bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.00001)
  bm.normal_update()
  if self.name in ['Arched_Roof_Surface','Snow_Accumulation']:
   for face in bm.faces:
    if face.normal.z<0:face.normal_flip()
  bm.normal_update()
  bm.to_mesh(me);bm.free();me.update()
  if self.name=='Arched_Roof_Surface':
   for p in me.polygons:p.use_smooth=True
  uv=me.uv_layers.new(name='UVMap')
  for p in me.polygons:
   axis=max(range(3),key=lambda k:abs(p.normal[k]));axes=[k for k in range(3) if k!=axis]
   for li in p.loop_indices:
    co=me.vertices[me.loops[li].vertex_index].co;uv.data[li].uv=(co.x*.4,co.y*.4) if self.name in ['Arched_Roof_Surface','Snow_Accumulation'] else (co[axes[0]]*.4,co[axes[1]]*.4)
  if radius:
   bpy.context.view_layer.objects.active=ob;mod=ob.modifiers.new('Fabricated edge bevel','BEVEL');mod.width=radius;mod.segments=2;mod.limit_method='ANGLE';bpy.ops.object.modifier_apply(modifier=mod.name)
   mod=ob.modifiers.new('Weighted normals','WEIGHTED_NORMAL');mod.keep_sharp=True;bpy.ops.object.modifier_apply(modifier=mod.name)
  return ob
scene=bpy.data.scenes.new('NorthernLab_RebuiltExterior');bpy.context.window.scene=scene;scene.unit_settings.system='METRIC'
MATS=[material('Arctic_Powdercoat',(.85,.87,.88),.12,.72),material('Graphite_Extrusions',(.07,.105,.13),.45,.58),material('StandingSeam_Steel',(.16,.225,.265),.42,.69),material('Gasket_Recess',(.016,.025,.032),.05,.94),material('Safety_Ochre',(.72,.24,.035),.15,.67),material('Stainless_Fixings',(.28,.34,.37),.75,.40),material('Windblown_Snow',(.82,.86,.88),0,.97)]
skin=Geo('Base_ExteriorShell_Mesh');frame=Geo('Structural_Trims');roof=Geo('StandingSeams');equip=Geo('Roof_TechnicalEquipment');bolts=Geo('Fasteners');snow=Geo('Snow_Accumulation');proxy=Geo('ShellCollisionProxy');arched=Geo('Arched_Roof_Surface')
def outline(b):
 x,z,X,Z=b;x-=.4;z-=.4;X+=.4;Z+=.4;c=.65
 return [(x+c,z),(X-c,z),(X,z+c),(X,Z-c),(X-c,Z),(x+c,Z),(x,Z-c),(x,z+c)]
def wall(name,edge,A,B,h):
 a,b=Vector((A[0],0,A[1])),Vector((B[0],0,B[1]));d=(b-a).normalized();normal=Vector((d.z,0,-d.x));length=(b-a).length;along=0 if abs(d.x)>.5 else 2
 holes=[]
 if name=='west' and edge==6:holes=[(2.08,3.92,3.15),(-5.68,.68,4.15)]
 if name=='hub' and edge in [0,2,4,6]:holes=[(-2.95,2.95,6.0)]
 if (name,edge) in [('west',2),('east',6),('north',4),('south',0)]:holes=[(-2.95,2.95,6.0)]
 count=math.ceil(length/1.8);stations=[length*i/count for i in range(count+1)]
 for lo,hi,top in holes:
  for co in [lo,hi]:
   t=(co-a[along])/d[along]
   if 0<t<length:stations.append(t)
 stations=sorted(set(stations));ys=sorted(set([-.32,.35,2.85,h]+[v[2] for v in holes if v[2]<h]))
 for t0,t1 in zip(stations,stations[1:]):
  if t1-t0<.025:continue
  mid=(a+d*((t0+t1)/2))[along]
  for y0,y1 in zip(ys,ys[1:]):
   if any(lo<mid<hi and (y0+y1)/2<top for lo,hi,top in holes):continue
   p0=a+d*t0+Vector((0,y0,0));p1=a+d*t1+Vector((0,y0,0));p2=a+d*t1+Vector((0,y1,0));p3=a+d*t0+Vector((0,y1,0));P=[p0,p1,p2,p3]
   skin.solid(P,.16,normal,3);proxy.solid([p+normal*.065 for p in P],.22,normal,0)
   inset=.018;P=[p0+d*inset+Vector((0,inset,0)),p1-d*inset+Vector((0,inset,0)),p2-d*inset-Vector((0,inset,0)),p3+d*inset-Vector((0,inset,0))]
   skin.solid([p+normal*.06 for p in P],.065,normal,0 if y0>.3 else 1)
  if not any(lo<mid<hi for lo,hi,top in holes):
   p=a+d*t0+normal*.095;frame.beam(p+Vector((0,.35,0)),p+Vector((0,h,0)),.065,1)
   for y in [.55,2.65,h-.2]:bolts.bolt(p+Vector((0,y,0))+normal*.045,normal)
  for y in [.18,h-.1]:
   if not any(lo<mid<hi and y<top for lo,hi,top in holes):frame.beam(a+d*t0+Vector((0,y,0))+normal*.10,a+d*t1+Vector((0,y,0))+normal*.10,.13,1)
def curved_roof(name,b,h,ridge):
 x,z,X,Z=b;along=name in ['west','east'];rise=ridge-h
 if name=='hub':
  def point(t,k):
   angle=k*math.tau/64;c=math.cos(angle);ss=math.sin(angle)
   return Vector(((x+X)/2+10.3*t*math.copysign(abs(c)**.25,c),h+rise*math.sqrt(max(0,1-t*t)),(z+Z)/2+10.3*t*math.copysign(abs(ss)**.25,ss)))
  for ring in range(1,17):
   t0=(ring-1)/16;t1=ring/16
   for k in range(64):
    P=[point(t0,k),point(t1,k),point(t1,k+1),point(t0,k+1)];arched.face(P,2);proxy.face(P,2)
  for k in range(64):frame.beam(point(1,k),point(1,k+1),.22,1)
  for k in range(0,64,4):
   for ring in range(1,17):roof.beam(point((ring-1)/16,k)+Vector((0,.04,0)),point(ring/16,k)+Vector((0,.04,0)),.045,1)
  return
 start,end=(x-.8,X+.8) if along else (z-.8,Z+.8)
 def point(t,v):
  across=(z-.8)+(Z-z+1.6)*v if along else (x-.8)+(X-x+1.6)*v
  return Vector((t,h+rise*math.sin(math.pi*v),across)) if along else Vector((across,h+rise*math.sin(math.pi*v),t))
 sections=math.ceil((end-start)/1.25)
 for j in range(sections):
  a=start+(end-start)*j/sections;bb=start+(end-start)*(j+1)/sections
  for k in range(32):
   P=[point(a,k/32),point(bb,k/32),point(bb,(k+1)/32),point(a,(k+1)/32)];arched.face(P,2);proxy.face(P,2)
 for j in range(sections+1):
  t=start+(end-start)*j/sections
  for k in range(32):roof.beam(point(t,k/32)+Vector((0,.04,0)),point(t,(k+1)/32)+Vector((0,.04,0)),.065 if j%4==0 else .028,1)
 for t in [start,end]:
  for k in range(32):
   a=point(t,k/32);bb=point(t,(k+1)/32);P=[Vector((a.x,h,a.z)),Vector((bb.x,h,bb.z)),bb,a]
   if k not in [0,31]:skin.solid(P,.12,(1,0,0) if along else (0,0,1),0);proxy.face(P,0)
 for v in [0,1]:frame.beam(point(start,v),point(end,v),.22,1)
 for j in range(sections*2):
  a=start+(end-start)*j/(sections*2);bb=start+(end-start)*(j+1)/(sections*2)
  va=.90+.025*math.sin(a*.7);vb=.90+.025*math.sin(bb*.7)
  snow.face([point(a,va)+Vector((0,.06,0)),point(bb,vb)+Vector((0,.06,0)),point(bb,1)+Vector((0,.06,0)),point(a,1)+Vector((0,.06,0))],6)

for name,b in REF['exterior_design_bounds'].items():
 h=8.95 if name=='hub' else 6.35;ridge=10.25 if name=='hub' else 8.15;points=outline(b)
 for edge in range(8):wall(name,edge,points[edge],points[(edge+1)%8],h)
 x,z,X,Z=b;along_x=name in ['west','east','hub'];C=[(x-.8,h,z-.8),(X+.8,h,z-.8),(X+.8,h,Z+.8),(x-.8,h,Z+.8)]
 if along_x:
  r0=(x+1.1,ridge,(z+Z)/2);r1=(X-1.1,ridge,(z+Z)/2);planes=[[C[0],C[1],r1,r0],[C[1],C[2],r1],[C[2],C[3],r0,r1],[C[3],C[0],r0]]
 else:
  r0=((x+X)/2,ridge,z+1.1);r1=((x+X)/2,ridge,Z-1.1);planes=[[C[0],C[1],r0],[C[1],C[2],r1,r0],[C[2],C[3],r1],[C[3],C[0],r0,r1]]
 curved_roof(name,b,h,ridge)
 cx=(x+X)/2;cz=(z+Z)/2;y=ridge+.15
 equip.box((cx-1.3,y-.12,cz-1.6,cx+1.3,y+.15,cz+1.6),1);equip.box((cx-1.12,y+.15,cz-1.4,cx+1.12,y+.95,cz+1.4),0);equip.box((cx-1.25,y+.95,cz-1.52,cx+1.25,y+1.12,cz+1.52),2)
 for side in [-1,1]:
  xx=cx+side*1.135;equip.box((xx-.018,y+.30,cz-1.06,xx+.018,y+.77,cz+1.06),3)
  for j in range(6):equip.beam((xx+side*.04,y+.32+j*.075,cz-1.03),(xx+side*.04,y+.32+j*.075,cz+1.03),.035,5)
  for zz in [-1.2,1.2]:bolts.bolt((xx+side*.04,y+.87,cz+zz),(side,0,0))
for axis,side in [('x',-1),('x',1),('z',-1),('z',1)]:
 a,b=(-10.6,-7.6) if side<0 else (7.6,10.6);ya,yb=(6.3,8.9) if side<0 else (8.9,6.3)
 for flank in [-1,1]:
  P=[(a,5.2,flank*2.9),(b,5.2,flank*2.9),(b,yb,flank*2.9),(a,ya,flank*2.9)] if axis=='x' else [(flank*2.9,5.2,a),(flank*2.9,5.2,b),(flank*2.9,yb,b),(flank*2.9,ya,a)]
  n=(0,0,flank) if axis=='x' else (flank,0,0);skin.solid(P,.16,n,1);proxy.solid(P,.16,n,1)
 P=[(a,ya,-2.92),(b,yb,-2.92),(b,yb,2.92),(a,ya,2.92)] if axis=='x' else [(-2.92,ya,a),(-2.92,yb,b),(2.92,yb,b),(2.92,ya,a)]
 skin.solid(P,.15,(0,1,0),2);proxy.solid(P,.15,(0,1,0),2)
for name,p in REF['portals'].items():
 xf=p['front_x'];xb=-38.5;lo=p['z_min'];hi=p['z_max'];top=p['top']
 for side,zz in [(-1,lo-.24),(1,hi+.24)]:equip.box((xf,-.3,zz-.13,xb+.05,top+.32,zz+.13),1);frame.beam((xf-.02,.15,zz),(xf-.02,top+.18,zz),.075,4)
 equip.box((xf,top+.13,lo-.37,xb+.15,top+.43,hi+.37),1)
 for zz in [lo-.1,hi+.1]:
  for y in [.4,top-.2]:bolts.bolt((xf-.035,y,zz),(-1,0,0),.045)
equip.box((-40.45,3.55,1.7,-38.25,3.72,4.35),2)
for zz in [1.9,4.1]:frame.beam((-38.6,2.85,zz),(-40.25,3.55,zz),.09,1)
# Backup solar rack supports match the existing separate panel instances.
for zz in [4.3,6.14,7.98]:
 equip.box((-40.12,-.25,zz-.10,-38.96,-.07,zz+.10),1)
 equip.box((-39.11,-.12,zz-.055,-38.99,1.44,zz+.055),1)
for y in [.43,1.16]:frame.beam((-39.15,y,4.30),(-39.15,y,7.98),.11,1)
# Roof maintenance walkway and practical safety rail, only on the service wing.
for i in range(14):
 xx=-29+i*.32;equip.box((xx,8.35,.9,xx+.24,8.40,1.8),1)
for xx in [-29,-27,-25]:
 frame.beam((xx,8.4,1.8),(xx,9.15,1.8),.045,5)
frame.beam((-29,9.15,1.8),(-24.6,9.15,1.8),.045,5)
# Separate risers and cable trays make the exterior's services legible.
for zz in [-6.9,-6.55]:
 frame.beam((-22,.55,zz),(-22,4.5,zz),.10,5)
 frame.beam((-22,4.5,zz),(-18.5,4.5,zz),.10,5)
for y in [.8,2.4,4.2]:equip.box((-22.15,y-.05,-7.12,-21.85,y+.05,-6.35),1)
for geo in GROUPS.values():
 if geo.v:OBJECTS.append(geo.object(.018 if geo.name not in ['ShellCollisionProxy','Snow_Accumulation','Fasteners','Arched_Roof_Surface'] else 0))
curve=bpy.data.curves.new('StationIdentity','FONT');curve.body='NORTHERNLAB  /  01';curve.size=.27;curve.extrude=.002
ob=bpy.data.objects.new('Entry_Identification',curve);scene.collection.objects.link(ob);ob.location=g((-40.47,3.36,1.9));ob.rotation_euler=Matrix(((0,0,-1),(-1,0,0),(0,1,0))).to_euler();curve.materials.append(MATS[4]);bpy.context.view_layer.objects.active=ob;ob.select_set(True);bpy.ops.object.convert(target='MESH');OBJECTS.append(bpy.context.object)
print('BUILT',len(OBJECTS),'objects',sum(len(o.data.polygons) for o in OBJECTS),'polygons',flush=True)
def finish():
 # Use authored trim sheets for cassettes and scanned PBR for exterior blue steel.
 for idx in [0,1,2,5,6]:
  m=MATS[idx];nodes=m.node_tree.nodes;p=next(n for n in nodes if n.type=='BSDF_PRINCIPLED')
  if idx==0:
   base=ROOT/'assets/models/modular_scifi_megakit/textures';paths=[base/'t_trim_02_base_color.png',base/'t_trim_02_normal.png',base/'t_trim_02_orm.png']
  elif idx==6:
   base=ROOT/'assets/environments/snow/snow006';paths=[base/'color.jpg',base/'normal_gl.jpg',base/'roughness.jpg']
  else:
   base=OUT/'pbr';paths=[base/'blue_metal_color.jpg',base/'blue_metal_normal.jpg',base/'blue_metal_roughness.jpg']
  for role,filename in zip(['color','normal','rough'],paths):
   tex=nodes.new('ShaderNodeTexImage');tex.image=bpy.data.images.load(str(filename),check_existing=True)
   if role!='color':tex.image.colorspace_settings.name='Non-Color'
   if role=='color':
    if idx in [0,2,6]:m.node_tree.links.new(tex.outputs['Color'],p.inputs['Base Color'])
   elif role=='normal':
    nm=nodes.new('ShaderNodeNormalMap');nm.inputs['Strength'].default_value=.65;m.node_tree.links.new(tex.outputs['Color'],nm.inputs['Color']);m.node_tree.links.new(nm.outputs['Normal'],p.inputs['Normal'])
   else:
    if idx==0:
     sep=nodes.new('ShaderNodeSeparateColor');m.node_tree.links.new(tex.outputs['Color'],sep.inputs['Color']);m.node_tree.links.new(sep.outputs['Green'],p.inputs['Roughness']);m.node_tree.links.new(sep.outputs['Blue'],p.inputs['Metallic'])
    else:m.node_tree.links.new(tex.outputs['Color'],p.inputs['Roughness'])
 # Trim-map UVs stay inside one cassette region, instead of tiling an entire atlas.
 for ob in OBJECTS:
  uv=ob.data.uv_layers.active
  if not uv:continue
  for poly in ob.data.polygons:
   if poly.material_index==0:
    coords=[ob.data.vertices[ob.data.loops[i].vertex_index].co for i in poly.loop_indices];axis=max(range(3),key=lambda k:abs(poly.normal[k]));axes=[k for k in range(3) if k!=axis];lo=[min(c[k] for c in coords) for k in axes];hi=[max(c[k] for c in coords) for k in axes]
    for li,c in zip(poly.loop_indices,coords):uv.data[li].uv=(.015+.47*(c[axes[0]]-lo[0])/max(.00001,hi[0]-lo[0]),.425+.30*(c[axes[1]]-lo[1])/max(.00001,hi[1]-lo[1]))
 with bpy.data.libraries.load(str(ROOT/'blender/arctic_base_exterior_shell/selected_antennas_reduced.blend'),link=False) as (src,dst):dst.objects=['Antenna_CentralLattice','Antenna_ScienceMast']
 for ob,pos,height in zip(dst.objects,[(0,11.5,0),(0,9.5,-19)],[6,3]):
  if ob:bpy.context.scene.collection.objects.link(ob);ob.location=g(pos);ob.scale=(height,height,height);ob.data.materials.clear();ob.data.materials.append(MATS[5]);OBJECTS.append(ob)
 exec(compile((ROOT/"blender/arctic_base_rebuild/refine_materials.py").read_text(encoding="utf-8-sig"),"refine_materials.py","exec"),globals())
 exec(compile((ROOT/"blender/arctic_base_rebuild/age_and_gate.py").read_text(encoding="utf-8-sig"),"age_and_gate.py","exec"),globals())
 exec(compile((ROOT/"blender/arctic_base_rebuild/finish_joints.py").read_text(encoding="utf-8-sig"),"finish_joints.py","exec"),globals())
 exec(compile((ROOT/"blender/arctic_base_rebuild/seal_roofs.py").read_text(encoding="utf-8-sig"),"seal_roofs.py","exec"),globals())
 exec(compile((ROOT/"blender/arctic_base_rebuild/refine_envelope.py").read_text(encoding="utf-8-sig"),"refine_envelope.py","exec"),globals())
 exec(compile((ROOT/"blender/arctic_base_rebuild/export_current.py").read_text(encoding="utf-8-sig"),"export_current.py","exec"),globals())
