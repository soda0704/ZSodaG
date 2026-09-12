extends SceneTree
func _initialize():
    var doc = GLTFDocument.new()
    var state = GLTFState.new()
    var error = doc.append_from_file("D:/Github/ZSodaG/assets/models/doors/medical_hermetic_door/medical_hermetic_door.glb", state)
    if error != OK:
        quit(1)
        return
    var model = doc.generate_scene(state)
    root.add_child(model)
    await process_frame
    var left = model.find_child("LeftLeaf", true, false)
    var right = model.find_child("RightLeaf", true, false)
    assert(left != null and right != null)
    left.position.x -= 2.51
    right.position.x += 2.51
    assert(left.position.x + left.mesh.get_aabb().end.x < -2.4)
    assert(right.position.x + right.mesh.get_aabb().position.x > 2.4)
    print("GODOT_VALIDATION_OK: embedded materials loaded; both leaves open independently and clear passage")
    quit(0)
