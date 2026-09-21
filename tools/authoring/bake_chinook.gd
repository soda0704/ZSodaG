extends SceneTree
# Offline authoring utility: rebuild static hull collision and ramp keyframes from the imported model.
# Never executed by game scenes. Re-run deliberately after replacing/reimporting the model.
func _initialize():
 run.call_deferred()
func run():
 var model = load("res://assets/models/vehicles/chinook/scene.gltf").instantiate()
 root.add_child(model)
 var faces := PackedVector3Array()
 for mesh_name in ["Retopo_Cube_013_Chinook_Exterior_0", "Retopo_Cube_017_Material_0", "Cylinder_008_Chinook_Exterior_0", "Cylinder_010_Chinook_Exterior_0"]:
  var mesh_node: MeshInstance3D = model.find_child(mesh_name, true, false)
  for vertex in mesh_node.mesh.get_faces():
   faces.append(mesh_node.global_transform * vertex)
 var shape := ConcavePolygonShape3D.new()
 shape.backface_collision = true
 shape.set_faces(faces)
 ResourceSaver.save(shape, "res://assets/models/vehicles/chinook/fuselage_collision.res")
 var ramp: Node3D = model.find_child("Retopo_Cube_036", true, false)
 var hinge := Vector3(-5.13, 1.04, 0)
 var library := AnimationLibrary.new()
 var animation := Animation.new()
 animation.length = 1.5
 var track := animation.add_track(Animation.TYPE_VALUE)
 animation.track_set_path(track, NodePath("Visual/" + str(model.get_path_to(ramp)) + ":transform"))
 animation.track_insert_key(track, 0, ramp.transform)
 var rotated := Transform3D(Basis(Vector3.BACK, deg_to_rad(64)), hinge)
 var from_hinge := Transform3D(Basis.IDENTITY, -hinge)
 animation.track_insert_key(track, 1.5, ramp.get_parent().global_transform.affine_inverse() * rotated * from_hinge * ramp.global_transform)
 track = animation.add_track(Animation.TYPE_VALUE)
 animation.track_set_path(track, NodePath("RearRamp:rotation"))
 animation.track_insert_key(track, 0, Vector3.ZERO)
 animation.track_insert_key(track, 1.5, Vector3(0, 0, deg_to_rad(64)))
 track = animation.add_track(Animation.TYPE_VALUE)
 animation.track_set_path(track, NodePath("RearRamp/ClosedPassage:disabled"))
 animation.value_track_set_update_mode(track, Animation.UPDATE_DISCRETE)
 animation.track_insert_key(track, 0, false)
 animation.track_insert_key(track, 1.5, true)
 library.add_animation("deploy", animation)
 ResourceSaver.save(library, "res://assets/models/vehicles/chinook/ramp_animations.tres")
 print("Baked hull triangles: ", faces.size()/3)
 quit()

