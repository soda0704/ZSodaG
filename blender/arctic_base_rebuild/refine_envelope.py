"""Calmer polar-station cladding, fitted portals and removal of interior artefacts."""
def remove_model(name):
 old=bpy.context.scene.objects.get(name)
 if old:
  OBJECTS[:]=[o for o in OBJECTS if o!=old];bpy.data.objects.remove(old,do_unlink=True)
for name in ['Base_ExteriorShell_Mesh','Structural_Trims','Fasteners','Joint_Flashings']:remove_model(name)
panels=Geo('Station_Insulated_Cladding');edges=Geo('Folded_Edge_Flashings');fixings=Geo('Panel_Fixings')
for name,bounds in REF['exterior_design_bounds'].items():
 points=outline(bounds);h=8.95 if name=='hub' else 6.35
 for k,A in enumerate(points):
  B=points[(k+1)%8];a=Vector((A[0],0,A[1]));b=Vector((B[0],0,B[1]));d=(b-a).normalized();n=Vector((d.z,0,-d.x));length=(b-a).length;along=0 if abs(d.x)>.5 else 2
  holes=[]
  if name=='west' and k==6:holes=[(2.08,3.92,3.15),(-5.31,.31,3.70)]
  if name=='hub' and k in [0,2,4,6]:holes=[(-2.95,2.95,6)]
  if (name,k) in [('west',2),('east',6),('north',4),('south',0)]:holes=[(-2.95,2.95,6)]
  rows=sorted(set([-.32,.38,1.88,3.38,4.88,h]+[p[2] for p in holes]))
  rows=[y for y in rows if y<=h]
  for row,(y0,y1) in enumerate(zip(rows,rows[1:])):
   # Offset the restrained vertical seams between horizontal insulated courses.
   cuts=[0,length];pitch=4.8;offset=(row%2)*pitch*.5
   for j in range(-1,math.ceil(length/pitch)+1):
    t=j*pitch+offset
    if .05<t<length-.05:cuts.append(t)
   for lo,hi,top in holes:
    for v in [lo,hi]:
     t=(v-a[along])/d[along]
     if 0<t<length:cuts.append(t)
   cuts=sorted(set(cuts))
   for t0,t1 in zip(cuts,cuts[1:]):
    if t1-t0<.025:continue
    mid=(a+d*((t0+t1)/2))[along]
    if any(lo<mid<hi and (y0+y1)/2<top for lo,hi,top in holes):continue
    P=[a+d*t0+Vector((0,y0,0)),a+d*t1+Vector((0,y0,0)),a+d*t1+Vector((0,y1,0)),a+d*t0+Vector((0,y1,0))]
    panels.solid(P,.18,n,0)
    inset=.008
    inset_pts=[P[0]+d*inset+Vector((0,inset,0)),P[1]-d*inset+Vector((0,inset,0)),P[2]-d*inset-Vector((0,inset,0)),P[3]+d*inset-Vector((0,inset,0))]
    panels.solid([p+n*.035 for p in inset_pts],.036,n,1 if y1<=.4 else 0)
    if t1-t0>1.0 and y1-y0>.25:
     for t in [t0+.10,t1-.10]:fixings.bolt(a+d*t+Vector((0,y1-.09,0))+n*.05,n,.014)
  # Folded flush corner cover; no exposed vertical cage around every cassette.
  prev=Vector((points[(k-1)%8][0],0,points[(k-1)%8][1]));pd=(a-prev).normalized();pn=Vector((pd.z,0,-pd.x));bis=(pn+n).normalized();middle=a+bis*.062
  for outer in [a-pd*.11+pn*.045,a+d*.11+n*.045]:edges.solid([outer+Vector((0,.38,0)),middle+Vector((0,.38,0)),middle+Vector((0,h-.08,0)),outer+Vector((0,h-.08,0))],.018,bis,0)
  for t0,t1 in [(0,length)]:
   if not holes:edges.beam(a+d*t0+n*.06+Vector((0,.18,0)),a+d*t1+n*.06+Vector((0,.18,0)),.08,1)
# Keep the existing measured module bridges, outside all four interior routes.
for axis,side in [('x',-1),('x',1),('z',-1),('z',1)]:
 a,b=(-10.6,-7.6) if side<0 else (7.6,10.6);ya,yb=(6.3,8.9) if side<0 else (8.9,6.3)
 for flank in [-1,1]:
  P=[(a,-.3,flank*2.9),(b,-.3,flank*2.9),(b,yb,flank*2.9),(a,ya,flank*2.9)] if axis=='x' else [(flank*2.9,-.3,a),(flank*2.9,-.3,b),(flank*2.9,yb,b),(flank*2.9,ya,a)]
  panels.solid(P,.16,(0,0,flank) if axis=='x' else (flank,0,0),0)
 P=[(a,ya,-2.92),(b,yb,-2.92),(b,yb,2.92),(a,ya,2.92)] if axis=='x' else [(-2.92,ya,a),(-2.92,yb,b),(2.92,yb,b),(2.92,ya,a)]
 panels.solid(P,.15,(0,1,0),2)
# Remove complete disconnected islands, never slice through a cabinet or panel.
equip_ob=bpy.context.scene.objects['Roof_TechnicalEquipment'];bm=bmesh.new();bm.from_mesh(equip_ob.data);seen=set();remove=[];removed=[]
for seed in bm.verts:
 if seed in seen:continue
 todo=[seed];part=[];seen.add(seed)
 while todo:
  v=todo.pop();part.append(v)
  for e in v.link_edges:
   other=e.other_vert(v)
   if other not in seen:seen.add(other);todo.append(other)
 lo=[min(v.co[k] for v in part) for k in range(3)];hi=[max(v.co[k] for v in part) for k in range(3)];center=[(a+b)/2 for a,b in zip(lo,hi)]
 walkway=lo[0]>-29.1 and hi[0]<-24.4 and lo[1]>-1.9 and hi[1]<-.8 and lo[2]>8.30 and hi[2]<8.46
 indoor_bracket=lo[0]>-22.2 and hi[0]<-21.8 and lo[1]>6.2 and hi[1]<7.2 and hi[2]<4.4
 old_portal=center[0]<-38.3 and 1.0<center[2]<4.6 and -4.9<center[1]<6.3
 if walkway or indoor_bracket or old_portal:remove+=part;removed.append((walkway,indoor_bracket,old_portal))
bmesh.ops.delete(bm,geom=remove,context='VERTS');bm.to_mesh(equip_ob.data);bm.free();equip_ob.data.update()
# Portal follows the actual animated 5.56 x 3.62 metre shutter, not the old wider prototype.
portal=Geo('Fitted_Entrance_Reveals')
for name,lo,hi,top,front in [('garage',-5.31,.31,3.70,-39.50),('entrance',2.08,3.92,3.15,-39.80)]:
 for zz in [lo-.13,hi+.13]:portal.box((front,0,zz-.13,-38.00,top+.18,zz+.13),0)
 portal.box((front,top,lo-.26,-38.00,top+.18,hi+.26),0)
 if name=='garage':
  # Narrow seals overlap the leaf by 1 cm. These are inside the deep reveal.
  for zz in [lo,hi]:portal.beam((-38.09,.05,zz),(-38.09,3.64,zz),.07,3)
  portal.beam((-38.09,3.64,lo),(-38.09,3.64,hi),.07,3)
for yy in [.43,1.16]:portal.beam((-39.15,yy,4.30),(-39.15,yy,7.98),.08,1)
new_objects=[panels.object(.008),edges.object(.008),fixings.object(),portal.object(.012)]
new_objects[0].name='Base_ExteriorShell_Mesh';new_objects[1].name='Joint_Flashings'
for ob in new_objects:
 me=ob.data;me.update();uv=me.uv_layers.active;colors=me.color_attributes.new(name='Weathering',type='FLOAT_COLOR',domain='CORNER');me.color_attributes.active_color=colors
 for p in me.polygons:
  axis=max(range(3),key=lambda k:abs(p.normal[k]));axes=[k for k in range(3) if k!=axis]
  for li in p.loop_indices:
   co=me.vertices[me.loops[li].vertex_index].co;uv.data[li].uv=(co[axes[0]]*.4,co[axes[1]]*.4)
   field=.5+.3*math.sin(co.x*.37+co.y*.27)+.2*math.sin(co.y*.73-co.x*.17);soil=max(0,1-max(0,co.z)/1.5)*(.18+.16*field);value=1-soil
   colors.data[li].color=(value*.16,value*.20,value*.23,1) if p.material_index==1 else (value*.98,value*.985,value,1)
OBJECTS+=new_objects
antenna=bpy.context.scene.objects['Antenna_CentralLattice'];antenna.scale=(14,14,14);antenna.location=g((0,10.25,0))
antenna=bpy.context.scene.objects['Antenna_ScienceMast'];antenna.scale=(6,6,6);antenna.location=g((0,8.15,-19))
# Supports are visibly seated on the roof rather than suspended above it.
pads=Geo('Antenna_Footings');pads.box((-1,10.15,-1,1,10.30,1),1);pads.box((-.9,8.05,-19.7,.9,8.20,-18.3),1)
pad_obj=pads.object(.02);OBJECTS.append(pad_obj)
colors=pad_obj.data.color_attributes.new(name='Weathering',type='FLOAT_COLOR',domain='CORNER');pad_obj.data.color_attributes.active_color=colors
for c in colors.data:c.color=(.16,.20,.23,1)
# Tighten the physical shell aperture to the fitted reveal, retaining the door's own blocker.
proxy_geo=Geo('Garage_Aperture_Infill')
for lo,hi in [(-5.68,-5.31),(.31,.68)]:proxy_geo.box((-38.68,-.30,lo,-38.35,4.15,hi),0)
proxy_geo.box((-38.68,3.70,-5.31,-38.35,4.15,.31),0)
infill=proxy_geo.object();proxy_ob=bpy.context.scene.objects['ShellCollisionProxy']
for o in bpy.context.scene.objects:o.select_set(False)
proxy_ob.hide_set(False);proxy_ob.select_set(True);infill.select_set(True);bpy.context.view_layer.objects.active=proxy_ob;bpy.ops.object.join()
print('REFINED ENVELOPE removed islands',len(removed),'new panels',len(panels.f),'central antenna height',14)
