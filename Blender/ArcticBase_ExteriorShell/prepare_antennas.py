"""Prepare ONLY three used antenna variants from the user archive (staging file stays tools/.local)."""
import bpy,bmesh,json
from pathlib import Path
from mathutils import Vector,Matrix
ROOT=Path(__file__).resolve().parents[2]
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'tools/.local/base-exterior/antenna-source/collection.blend'))
selected={'antenna1':8500,'antenna20':1800,'antenna25':900};original={}
# Keep world transforms before removing the Sketchfab root.
for o in list(bpy.data.objects):
 if o.type=='MESH':
  mw=o.matrix_world.copy();o.parent=None;o.matrix_world=mw
for o in list(bpy.data.objects):
 if o.type!='MESH' or o.name.split('_')[0] not in selected or any(t in o.name for t in ['Decals','Grid','Cloth']):bpy.data.objects.remove(o,do_unlink=True)
mat=bpy.data.materials.new('M_AntennaPaint');mat.diffuse_color=(.24,.29,.32,1);mat.use_nodes=True
bs=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED');bs.inputs['Base Color'].default_value=mat.diffuse_color;bs.inputs['Metallic'].default_value=.38;bs.inputs['Roughness'].default_value=.74
stats=[]
for key,target in selected.items():
 obs=[o for o in bpy.data.objects if o.type=='MESH' and o.name.startswith(key+'_')]
 bpy.ops.object.select_all(action='DESELECT')
 for o in obs:o.select_set(True)
 bpy.context.view_layer.objects.active=obs[0];bpy.ops.object.join();o=bpy.context.object
 mw=o.matrix_world.copy();pts=[mw@v.co for v in o.data.vertices];lo=Vector(tuple(min(p[k] for p in pts) for k in range(3)));hi=Vector(tuple(max(p[k] for p in pts) for k in range(3)))
 for v in o.data.vertices:v.co=(mw@v.co-Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z)))/(hi.z-lo.z)
 o.matrix_world=Matrix.Identity(4);o.data.materials.clear();o.data.materials.append(mat)
 for p in o.data.polygons:p.material_index=0
 o.data.calc_loop_triangles();before=len(o.data.loop_triangles)
 bm=bmesh.new();bm.from_mesh(o.data);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.000001);bm.to_mesh(o.data);bm.free()
 mod=o.modifiers.new('Silhouette budget','DECIMATE');mod.ratio=min(1,target/before);mod.use_collapse_triangulate=True;bpy.ops.object.modifier_apply(modifier=mod.name)
 bm=bmesh.new();bm.from_mesh(o.data);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.000001);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(o.data);bm.free()
 o.data.validate(verbose=True,clean_customdata=True);o.data.update()
 o.name={'antenna1':'Antenna_CentralLattice','antenna20':'Antenna_ScienceMast','antenna25':'Antenna_CrossArray'}[key]
 o.data.calc_loop_triangles();stats.append({'source':key,'name':o.name,'source_triangles':before,'triangles':len(o.data.loop_triangles),'height':1})
# Purge all unreferenced imported objects, images and original texture material datablocks.
bpy.ops.outliner.orphans_purge(do_recursive=True)
bpy.ops.wm.save_as_mainfile(filepath=str(Path(__file__).parent/'Selected_Antennas_Reduced.blend'))
(Path(__file__).parent/'antenna_reduction_stats.json').write_text(json.dumps(stats,indent=2)+'\n')
print('ANTENNA_STATS',stats)
