"""Run offline with Blender. Source archives remain untouched in Downloads.
Prepared glTF assets are scene visuals; this tool does not run in the game.
"""
import bpy, math, json, zipfile, hashlib, shutil, runpy
from pathlib import Path
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/"assets/models/heavy_props"
OUT.mkdir(parents=True,exist_ok=True)
REPORT={}
STAGE=ROOT/"tools/.local/heavy-props-export"
# Read the user's source archives as data; never execute bundled scripts.
for label,archive in [("joists","heavily_damaged_reinforced_concrete_joists-31d19757-textures.zip"),("workbench","workbench_sci-fi_lowpoly-861378b3-textures.zip")]:
 folder=ROOT/"tools/.local/heavy-props-source"/label
 required=folder/("file.osgjs" if label=="joists" else "model.gltf")
 if not required.exists():
  with zipfile.ZipFile(Path("E:/Downloads")/archive) as source:
   for entry in source.infolist():
    if entry.filename in ["model.gltf","model.bin","file.osgjs","info.json","README.txt"] or entry.filename.startswith("textures/"):
     destination=(folder/entry.filename).resolve()
     if folder.resolve() not in destination.parents:raise ValueError("Unsafe archive path")
     source.extract(entry,folder)

def load(path):
 bpy.ops.wm.read_factory_settings(use_empty=True)
 bpy.ops.import_scene.gltf(filepath=str(path))
 objs=[o for o in bpy.context.scene.objects if o.type=="MESH"]
 for o in objs:
  m=o.matrix_world.copy();o.parent=None;o.matrix_world=Matrix.Identity(4);o.data.transform(m)
 return objs
def bounds(objs):
 pts=[v.co for o in objs for v in o.data.vertices]
 return Vector([min(v[i] for v in pts) for i in range(3)]),Vector([max(v[i] for v in pts) for i in range(3)])
def tris(o):
 o.data.calc_loop_triangles();return len(o.data.loop_triangles)
def repair_download_materials(folder):
 # Downloader composites alpha and omits the separate roughness map. Use the
 # supplied original PBR maps instead of turning solid metal translucent.
 for mat in bpy.data.materials:
  if not mat.use_nodes:continue
  bsdf=next((n for n in mat.node_tree.nodes if n.type=="BSDF_PRINCIPLED"),None)
  if not bsdf:continue
  rough=folder/("Volume14_roughness.jpg" if mat.name.startswith("Volume14") else "DefaultMaterial_Roughness.png" if mat.name.startswith("roxory") else "T_Workbench_Rough.png")
  if rough.exists():
   node=mat.node_tree.nodes.new("ShaderNodeTexImage");node.image=bpy.data.images.load(str(rough),check_existing=True);node.image.colorspace_settings.name="Non-Color"
   mat.node_tree.links.new(node.outputs["Color"],bsdf.inputs["Roughness"])
  if mat.name.startswith("M_Workbench"):
   for node in mat.node_tree.nodes:
    if node.type=="TEX_IMAGE" and node.image and "diff_alpha" in node.image.name:node.image=bpy.data.images.load(str(folder/"T_workbench_diff.png"),check_existing=True)

def resize_textures():
 for i in bpy.data.images:
  if i.size[0]>2048 or i.size[1]>2048:
   ratio=2048/max(i.size);i.scale(round(i.size[0]*ratio),round(i.size[1]*ratio))
  if not i.packed_file and i.has_data:i.pack()
def finish(name,objs,length,turn=False,ratio=1):
 bpy.ops.object.select_all(action="DESELECT")
 for o in objs:o.select_set(True)
 bpy.context.view_layer.objects.active=objs[0]
 if len(objs)>1:bpy.ops.object.join()
 o=bpy.context.object;o.name=name
 if turn:o.data.transform(Matrix.Rotation(math.pi/2,4,"Z"))
 lo,hi=bounds([o]);scale=length/(hi.x-lo.x)
 floor=lo.z
 if name.startswith("concrete"):
  indices=set()
  for face in o.data.polygons:
   material=o.data.materials[face.material_index]
   if material and material.name.startswith("Volume14"):indices.update(face.vertices)
  if indices:floor=min(o.data.vertices[i].co.z for i in indices)
 center=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,floor))
 for v in o.data.vertices:v.co=(v.co-center)*scale
 o.data.update()
 before=tris(o)
 bpy.ops.object.mode_set(mode="EDIT");bpy.ops.mesh.select_all(action="SELECT")
 bpy.ops.mesh.remove_doubles(threshold=0.00002)
 bpy.ops.object.mode_set(mode="OBJECT")
 # Preserve material boundaries, UVs and the external silhouette. Accept a
 # reduction only while sampled surface deviation stays within 8 mm for large joists (5 mm for furniture).
 if ratio<1:
  original=o.data.copy()
  reference=BVHTree.FromPolygons([v.co for v in original.vertices],[list(p.vertices) for p in original.polygons])
  chosen=ratio
  for attempt in range(5):
   if attempt:o.data=original.copy()
   mod=o.modifiers.new("Offline reduction","DECIMATE");mod.ratio=chosen
   bpy.ops.object.modifier_apply(modifier=mod.name)
   reduced=BVHTree.FromPolygons([v.co for v in o.data.vertices],[list(p.vertices) for p in o.data.polygons])
   sample=list(original.vertices)[::max(1,len(original.vertices)//12000)]
   deviation=max((reduced.find_nearest(v.co)[3] or 0) for v in sample)
   if deviation <= (0.008 if name.startswith("concrete") else 0.005):break
   chosen=min(1,chosen*1.7)
  if deviation > (0.008 if name.startswith("concrete") else 0.005):o.data=original.copy();deviation=0
 else:deviation=0
 o.data.validate()
 lo,hi=bounds([o]);resize_textures()
 stage=STAGE/name
 stage.mkdir(parents=True,exist_ok=True)
 bpy.ops.export_scene.gltf(filepath=str(stage/(name+".gltf")),export_format="GLTF_SEPARATE",use_selection=True,export_yup=True,export_materials="EXPORT",export_animations=False,export_cameras=False,export_lights=False)
 REPORT[name]=dict(original_triangles=before,triangles=tris(o),sampled_deviation_m=deviation,size_blender=list(hi-lo))
 return o
objs=load(ROOT/"tools/.local/heavy-props-source/joists/model.gltf")
# The downloaded flat glTF omits OSG node matrices, leaving all rebar at
# the origin. Recover the original hierarchy before grouping the two joists.
osg=json.loads((ROOT/"tools/.local/heavy-props-source/joists/file.osgjs").read_text(encoding="utf8"))
matrices={}
def visit(value,matrix):
 if isinstance(value,list):
  for child in value:visit(child,matrix)
 elif isinstance(value,dict):
  for key,child in value.items():
   if key=="osg.MatrixTransform":
    raw=child.get("Matrix")
    local=Matrix([raw[i:i+4] for i in range(0,16,4)]).transposed() if raw else Matrix.Identity(4)
    visit(child,matrix@local)
   elif key=="osg.Geometry":
    if child.get("Name") not in matrices:matrices[child.get("Name")]=matrix
   elif isinstance(child,(dict,list)):visit(child,matrix)
visit(osg,Matrix.Identity(4))
for o in objs:
 o.data.transform(Matrix.Rotation(math.pi/2,4,"X")@matrices[o.name])
 o.data.update()
repair_download_materials(ROOT/"tools/.local/heavy-props-source/joists/textures")
slabs=[o for o in objs if o.name.startswith("slab")]
centers={o.name:sum((v.co for v in o.data.vertices),Vector())/len(o.data.vertices) for o in slabs}
groups={name:[] for name in centers}
for o in objs:
 c=sum((v.co for v in o.data.vertices),Vector())/len(o.data.vertices)
 name=min(centers,key=lambda n:(c-centers[n]).length);groups[name].append(o)
for index,(name,parts) in enumerate(sorted(groups.items())):finish("concrete_joist_"+str(index+1),parts,5.6,ratio=.07)
objs=load(ROOT/"tools/.local/heavy-props-source/workbench/model.gltf")
repair_download_materials(ROOT/"tools/.local/heavy-props-source/workbench/textures")
finish("powered_workbench",objs,2.4,ratio=1)
objs=load(ROOT/"Blender/East_Living/CommonRoom/sofa_grey_fabric.glb")
finish("sofa",objs,2.5,turn=True,ratio=.35)
objs=load(ROOT/"Blender/East_Living/CommonRoom/old_bench.glb")
finish("bench",objs,3.2,turn=True,ratio=1)
# Keep one copy of identical material maps across both joists. glTF references
# the shared textures directly, avoiding embedded+extracted duplicate images.
textures=OUT/"textures"
textures.mkdir(exist_ok=True)
known={}
for name in REPORT:
 stage=STAGE/name
 document=json.loads((stage/(name+".gltf")).read_text())
 for image in document.get("images",[]):
  source=stage/image["uri"]
  digest=hashlib.sha256(source.read_bytes()).hexdigest()
  if digest not in known:
   target=textures/(name+"_"+source.name)
   shutil.copyfile(source,target)
   known[digest]=target
  image["uri"]="textures/"+known[digest].name
 for buffer in document.get("buffers",[]):shutil.copyfile(stage/buffer["uri"],OUT/buffer["uri"])
 (OUT/(name+".gltf")).write_text(json.dumps(document),encoding="utf8")
cleanup = runpy.run_path(str(ROOT/"tools/authoring/remove_joist_stray_rebar.py"))
REPORT["concrete_joist_1"]["triangles"] -= cleanup["clean"]()
cleaned = json.loads((OUT/"concrete_joist_1.gltf").read_text(encoding="utf8"))
positions = [cleaned["accessors"][p["attributes"]["POSITION"]] for m in cleaned["meshes"] for p in m["primitives"]]
size = [max(a["max"][i] for a in positions)-min(a["min"][i] for a in positions) for i in range(3)]
REPORT["concrete_joist_1"]["size_blender"] = [size[0],size[2],size[1]]
(OUT/"preparation.json").write_text(json.dumps(REPORT,indent=2),encoding="utf8")
print("HEAVY ASSETS READY",json.dumps(REPORT))
