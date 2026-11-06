"""Final coated-metal response and non-degenerate UVs. Execute in author_rebuild namespace."""
for idx in [0,2]:
 m=MATS[idx];p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
 for link in list(p.inputs['Metallic'].links):m.node_tree.links.remove(link)
 p.inputs['Metallic'].default_value=.02
 for n in m.node_tree.nodes:
  if n.type=='NORMAL_MAP':n.inputs['Strength'].default_value=.22 if idx==0 else .35
 old=p.inputs['Roughness'].links[0].from_node
 if idx==0:old=next(n for n in m.node_tree.nodes if n.type=='TEX_IMAGE' and 'orm' in n.image.name)
 im=old.image;pixels=np.array(im.pixels[:],dtype=np.float32).reshape(im.size[1],im.size[0],4);value=pixels[:,:,1] if idx==0 else pixels[:,:,0];a=np.ones_like(pixels);a[:,:,:3]=(.55+.35*value)[:,:,None]
 out=bpy.data.images.new('CoatedRoughness_'+str(idx),width=im.size[0],height=im.size[1]);out.colorspace_settings.name='Non-Color';out.pixels.foreach_set(a.ravel());out.filepath_raw=str(OUT/('coat_roughness_'+str(idx)+'.png'));out.file_format='PNG';out.save()
 tex=m.node_tree.nodes.new('ShaderNodeTexImage');tex.image=out;m.node_tree.links.new(tex.outputs['Color'],p.inputs['Roughness'])
for ob in OBJECTS:
 me=ob.data;me.update();uv=me.uv_layers.active
 if not uv:continue
 for p in me.polygons:
  coords=[me.vertices[me.loops[i].vertex_index].co for i in p.loop_indices];axis=max(range(3),key=lambda k:abs(p.normal[k]));axes=[k for k in range(3) if k!=axis];lo=[min(c[k] for c in coords) for k in axes];hi=[max(c[k] for c in coords) for k in axes]
  for li,c in zip(p.loop_indices,coords):
   if ob.name in ['Arched_Roof_Surface','Snow_Accumulation']:uv.data[li].uv=(c.x*.4,c.y*.4)
   elif p.material_index==0 and p.area>.08:uv.data[li].uv=(.015+.47*(c[axes[0]]-lo[0])/max(.00001,hi[0]-lo[0]),.425+.30*(c[axes[1]]-lo[1])/max(.00001,hi[1]-lo[1]))
   elif p.material_index==0:uv.data[li].uv=(.24+c[axes[0]]*.002,.60+c[axes[1]]*.002)
   else:uv.data[li].uv=(c[axes[0]]*.4,c[axes[1]]*.4)
