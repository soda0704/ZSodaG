"""Export selected authored groups and the independently animated gate."""
for o in bpy.context.scene.objects:o.select_set(False)
gate_obj=bpy.data.objects['Garage_Insulated_Shutter'];gate_obj.hide_set(False);gate_obj.hide_render=False;gate_obj.select_set(True);bpy.context.view_layer.objects.active=gate_obj
bpy.ops.export_scene.gltf(filepath=str(OUT/'garage_shutter.glb'),export_format='GLB',use_selection=True,use_active_scene=True,export_vertex_color='ACTIVE',export_texcoords=True,export_normals=True,export_materials='EXPORT',export_apply=True)
gate_obj.hide_set(True);gate_obj.hide_render=True;gate_obj.select_set(False)
for o in OBJECTS:o.hide_set(False);o.hide_render=False;o.select_set(True)
bpy.context.view_layer.objects.active=OBJECTS[0]
bpy.ops.export_scene.gltf(filepath=str(OUT/'arctic_base_rebuild.glb'),export_format='GLB',use_selection=True,use_active_scene=True,export_vertex_color='ACTIVE',export_texcoords=True,export_normals=True,export_materials='EXPORT',export_apply=True)
bpy.data.objects['ShellCollisionProxy'].hide_set(True);bpy.data.objects['ShellCollisionProxy'].hide_render=True
stats={'objects':len(OBJECTS),'triangles':sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in OBJECTS),'materials':len(MATS),'gate_triangles':sum(len(p.vertices)-2 for p in gate_obj.data.polygons)}
(OUT/'model_stats.json').write_text(json.dumps(stats,indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'blender/arctic_base_rebuild/arctic_base_rebuild.blend'))
print('EXPORTED CURRENT',stats)
