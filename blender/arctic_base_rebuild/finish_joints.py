"""Folded exterior flashings, after age_and_gate.py; no gameplay collision changes."""
joint=Geo('Joint_Flashings')
for name,bounds in REF['exterior_design_bounds'].items():
 points=outline(bounds);h=8.95 if name=='hub' else 6.35
 for k,A in enumerate(points):
  B=points[(k+1)%8];Prev=points[(k-1)%8]
  center=Vector((A[0],0,A[1]));next_dir=(Vector((B[0],0,B[1]))-center).normalized();prev_dir=(center-Vector((Prev[0],0,Prev[1]))).normalized()
  n1=Vector((prev_dir.z,0,-prev_dir.x));n2=Vector((next_dir.z,0,-next_dir.x));bis=(n1+n2).normalized()
  middle=center+bis*.135
  for outer in [center-prev_dir*.18+n1*.105,center+next_dir*.18+n2*.105]:
   joint.solid([outer+Vector((0,.30,0)),middle+Vector((0,.30,0)),middle+Vector((0,h-.11,0)),outer+Vector((0,h-.11,0))],.025,bis,1)
  # Horizontal drip bead covers the upper cassette seam, except at apertures.
  d=next_dir;length=(Vector((B[0],0,B[1]))-center).length
  along=0 if abs(d.x)>.5 else 2
  holes=[]
  if name=='west' and k==6:holes=[(2.08,3.92),(-5.68,.68)]
  if name=='hub' and k in [0,2,4,6]:holes=[(-2.95,2.95)]
  if (name,k) in [('west',2),('east',6),('north',4),('south',0)]:holes=[(-2.95,2.95)]
  cuts=[0,length]
  for lo,hi in holes:
   for v in [lo,hi]:
    t=(v-center[along])/d[along]
    if 0<t<length:cuts.append(t)
  cuts=sorted(cuts)
  for a,b in zip(cuts,cuts[1:]):
   mid=(center+d*((a+b)/2))[along]
   if any(lo<mid<hi for lo,hi in holes):continue
   joint.beam(center+d*a+n2*.11+Vector((0,2.85,0)),center+d*b+n2*.11+Vector((0,2.85,0)),.05,1)
ob=joint.object(.009);OBJECTS.append(ob)
# glTF does not preserve a constant inside a VertexColor/Mix graph.
# Store the graphite tint in the attribute itself so its export matches Blender.
for ob in OBJECTS+[bpy.data.objects['Garage_Insulated_Shutter']]:
 colors=ob.data.color_attributes.get('Weathering')
 if colors is None:
  colors=ob.data.color_attributes.new(name='Weathering',type='FLOAT_COLOR',domain='CORNER');ob.data.color_attributes.active_color=colors
  for c in colors.data:c.color=(1,1,1,1)
 for p in ob.data.polygons:
  if p.material_index==1:
   for li in p.loop_indices:
    co=ob.data.vertices[ob.data.loops[li].vertex_index].co
    field=.5+.3*math.sin(co.x*.87+co.y*.33)+.2*math.sin(co.y*1.77-co.x*.28)
    soil=max(0,1-max(0,co.z)/2)*(.18+.15*field)
    streak=(.5+.5*math.sin(co.x*5.9+co.y*3.7))**8*.05
    value=max(.52,1-soil-streak)
    colors.data[li].color=(value*.16,value*.20,value*.23,1)
m=MATS[1];p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
mix=p.inputs['Base Color'].links[0].from_node
mix.inputs[1].default_value=(1,1,1,1)
print('FOLDED JOINT FLASHINGS',len(joint.f))
