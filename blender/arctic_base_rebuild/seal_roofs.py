"""Closed roof volumes: continuous curved skin, full gables and sealed soffits."""
roof_geo=Geo('Closed_Roof_Volumes');cap_geo=Geo('Roof_Collision_Closures')
for name,b in REF['exterior_design_bounds'].items():
 x,z,X,Z=b;h=8.95 if name=='hub' else 6.35;ridge=10.25 if name=='hub' else 8.15;rise=ridge-h
 if name=='hub':
  def point(t,k):
   angle=(k%128)*math.tau/128;c=math.cos(angle);s=math.sin(angle)
   if abs(c)<1e-10:c=0.0
   if abs(s)<1e-10:s=0.0
   return Vector(((x+X)/2+10.3*t*math.copysign(abs(c)**.25,c),h+rise*math.sqrt(max(0,1-t*t)),(z+Z)/2+10.3*t*math.copysign(abs(s)**.25,s)))
  for ring in range(1,33):
   for k in range(128):
    pts=[point((ring-1)/32,k),point(ring/32,k),point(ring/32,k+1),point((ring-1)/32,k+1)]
    if ring==1:pts=pts[1:]+[pts[0]];pts=pts[:3]
    roof_geo.face(pts,2)
  bottom=[]
  for k in range(128):
   a=point(1,k);b0=point(1,k+1);aa=Vector((a.x,h-.16,a.z));bb=Vector((b0.x,h-.16,b0.z));bottom.append(aa)
   roof_geo.face([a,b0,bb,aa],1);cap_geo.face([a,b0,bb,aa],1)
  roof_geo.face(list(reversed(bottom)),1);cap_geo.face(list(reversed(bottom)),1)
 else:
  along=name in ['west','east'];start,end=(x-.8,X+.8) if along else (z-.8,Z+.8)
  def point(t,v):
   across=(z-.8)+(Z-z+1.6)*v if along else (x-.8)+(X-x+1.6)*v
   return Vector((t,h+rise*math.sin(math.pi*v),across)) if along else Vector((across,h+rise*math.sin(math.pi*v),t))
  sections=math.ceil((end-start)/1.25)
  for j in range(sections):
   a=start+(end-start)*j/sections;bb=start+(end-start)*(j+1)/sections
   for k in range(64):roof_geo.face([point(a,k/64),point(bb,k/64),point(bb,(k+1)/64),point(a,(k+1)/64)],2)
  for t in [start,end]:
   curve=[point(t,k/64) for k in range(65)];last=curve[-1].copy();first=curve[0].copy();last.y=h-.16;first.y=h-.16
   roof_geo.face(curve+[last,first],0);cap_geo.face(curve+[last,first],0)
  for v in [0,1]:
   for j in range(sections):
    a=point(start+(end-start)*j/sections,v);bb=point(start+(end-start)*(j+1)/sections,v);aa=a.copy();bbb=bb.copy();aa.y=h-.16;bbb.y=h-.16
    roof_geo.face([a,bb,bbb,aa],1);cap_geo.face([a,bb,bbb,aa],1)
  for j in range(sections):
   a=start+(end-start)*j/sections;bb=start+(end-start)*(j+1)/sections
   bottom=[point(a,0),point(bb,0),point(bb,1),point(a,1)]
   for v in bottom:v.y=h-.16
   roof_geo.face(list(reversed(bottom)),1);cap_geo.face(list(reversed(bottom)),1)
# Remove obsolete fragmented gable skin, so the replacement cannot z-fight.
skin_ob=bpy.context.scene.objects['Base_ExteriorShell_Mesh'];bm=bmesh.new();bm.from_mesh(skin_ob.data)
remove=[]
for f in bm.faces:
 for name,b in REF['exterior_design_bounds'].items():
  if name=='hub':continue
  x,z,X,Z=b;axis=0 if name in ['west','east'] else 1;limits=[x-.8,X+.8] if axis==0 else [-z+.8,-Z-.8]
  if min(v.co.z for v in f.verts)>6.32 and any(all(abs(v.co[axis]-t)<.15 for v in f.verts) for t in limits):remove.append(f);break
bmesh.ops.delete(bm,geom=remove,context='FACES');bm.to_mesh(skin_ob.data);bm.free();skin_ob.data.update()
old=bpy.context.scene.objects['Arched_Roof_Surface'];OBJECTS[:]=[o for o in OBJECTS if o!=old];bpy.data.objects.remove(old,do_unlink=True)
new=roof_geo.object();new.name='Arched_Roof_Surface';me=new.data
bm=bmesh.new();bm.from_mesh(me);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.00001);bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=.000001);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(me)
boundary=sum(e.is_boundary for e in bm.edges);nonmanifold=sum(not e.is_manifold for e in bm.edges);bm.free();me.update()
if boundary or nonmanifold:raise RuntimeError('Roof closure failed: '+str((boundary,nonmanifold)))
uv=me.uv_layers.active
for p in me.polygons:
 p.use_smooth=p.material_index==2
 axis=max(range(3),key=lambda k:abs(p.normal[k]));axes=[k for k in range(3) if k!=axis]
 for li in p.loop_indices:
  co=me.vertices[me.loops[li].vertex_index].co
  uv.data[li].uv=(co.x*.4,co.y*.4) if p.material_index==2 else (co[axes[0]]*.4,co[axes[1]]*.4)
colors=me.color_attributes.new(name='Weathering',type='FLOAT_COLOR',domain='CORNER');me.color_attributes.active_color=colors
for p in me.polygons:
 for li in p.loop_indices:colors.data[li].color=(.16,.20,.23,1) if p.material_index==1 else (.96,.97,.98,1)
OBJECTS.append(new)
# Closures only, using the existing simplified collision roof on top.
cap=cap_geo.object();cap.name='Roof_Collision_Closures';cap.data.materials.clear()
proxy_ob=bpy.context.scene.objects['ShellCollisionProxy']
for o in bpy.context.scene.objects:o.select_set(False)
proxy_ob.hide_set(False);proxy_ob.select_set(True);cap.select_set(True);bpy.context.view_layer.objects.active=proxy_ob;bpy.ops.object.join()
OBJECTS[:]=[bpy.context.scene.objects[o.name] for o in OBJECTS]
(OUT/'roof_topology.json').write_text(json.dumps({'boundary_edges':boundary,'nonmanifold_edges':nonmanifold,'closed_components':5,'roof_triangles':sum(len(p.vertices)-2 for p in me.polygons)},indent=2))
print('CLOSED ROOFS',boundary,nonmanifold,len(me.polygons),'removed fragmented gables',len(remove))
