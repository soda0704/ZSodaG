import bpy, bmesh, random, math, json, os
from mathutils import Vector

OUT = 'D:/Github/ZSodaG/assets/models/environment/polar_fractured_ice'
collection = bpy.data.collections.new('Polar Fracture Studies')
bpy.context.scene.collection.children.link(collection)
results = []
for variant in range(5):
    rng = random.Random(817 + variant * 71)
    bm = bmesh.new()
    count = 7 + variant % 3
    outline = []
    for i in range(count):
        angle = math.tau * i / count + rng.uniform(-.12,.12)
        radius = rng.uniform(.75,1.05)
        outline.append((math.cos(angle)*radius, math.sin(angle)*radius))
    for x,y in outline:
        bm.verts.new((x*.82,y*.85,0))
        bm.verts.new((x,y,.28+rng.uniform(-.05,.05)))
        bm.verts.new((x*.78+.12,y*.84,.76+x*.18-y*.12+rng.uniform(-.07,.07)))
    bm.verts.new((-.15,.1,1.05))
    hull=bmesh.ops.convex_hull(bm,input=list(bm.verts))
    bmesh.ops.delete(bm,geom=hull.get('geom_interior',[]),context='VERTS')
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    mesh=bpy.data.meshes.new('FracturedIce_%02d'%variant)
    bm.to_mesh(mesh);bm.free()
    obj=bpy.data.objects.new(mesh.name,mesh);collection.objects.link(obj)
    bpy.context.view_layer.objects.active=obj
    obj.select_set(True)
    bevel=obj.modifiers.new('Small chipped edges','BEVEL');bevel.width=.018;bevel.segments=2
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    obj.data.calc_loop_triangles()
    verts=[v.co for v in obj.data.vertices]
    lo=Vector(tuple(min(v[k] for v in verts) for k in range(3)))
    hi=Vector(tuple(max(v[k] for v in verts) for k in range(3)))
    triangles=[]
    for tri in obj.data.loop_triangles:
        # GL/Godot conversion, clockwise winding for Godot.
        for index in (tri.vertices[0],tri.vertices[2],tri.vertices[1]):
            v=obj.data.vertices[index].co
            triangles.append([(v.x-lo.x)/(hi.x-lo.x)-.5,(v.z-lo.z)/(hi.z-lo.z),-((v.y-lo.y)/(hi.y-lo.y)-.5)])
    results.append(triangles)
    obj.location.x=variant*3
    obj.select_set(False)
with open(os.path.join(OUT,'fracture_geometry.json'),'w') as f: json.dump(results,f)
bpy.ops.wm.save_as_mainfile(filepath='D:/Github/ZSodaG/blender/polar_ice/polar_fractures.blend')
print('Authored 5 beveled fractured meshes:',[len(x)//3 for x in results])
