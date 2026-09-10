extends SceneTree

func _initialize():
    var document = GLTFDocument.new()
    var state = GLTFState.new()
    var path = ProjectSettings.globalize_path("res://../../../assets/models/doors/living_hermetic_door/living_hermetic_door.glb")
    var error = document.append_from_file(path, state)
    assert(error == OK, "GLB failed to load")
    var model = document.generate_scene(state)
    root.add_child(model)
    var assembly = model if model.name == "LivingHermeticDoor" else model.find_child("LivingHermeticDoor", true, false)
    assert(assembly != null, "Root missing")
    var names = ["Frame", "FrameSeals", "LeftLeaf", "RightLeaf", "FrontStatusLamps", "BackStatusLamps", "Socket_FrontAccessPanel", "Socket_BackAccessPanel"]
    for item in names:
        assert(assembly.get_node_or_null(NodePath(item)) != null, "Missing node: " + item)
    var left = assembly.get_node("LeftLeaf")
    var right = assembly.get_node("RightLeaf")
    assert(left.position.is_equal_approx(Vector3(-0.595, 1.35, 0)))
    assert(right.position.is_equal_approx(Vector3(0.595, 1.35, 0)))
    assert(left.has_node("CenterSeal_Front") and left.has_node("CenterSeal_Back"))
    assert(assembly.get_node("Socket_FrontAccessPanel").position.is_equal_approx(Vector3(1.720, 1.483, 0.2)))
    assert(assembly.get_node("Socket_BackAccessPanel").position.is_equal_approx(Vector3(-1.720, 1.483, -0.2)))
    var seal_offset = left.get_node("CenterSeal_Front").position
    left.position.x = -1.850
    right.position.x = 1.850
    assert(left.get_node("CenterSeal_Front").position.is_equal_approx(seal_offset))
    assert(left.position.x + left.mesh.get_aabb().end.x < -1.2)
    assert(right.position.x + right.mesh.get_aabb().position.x > 1.2)
    var material_names = []
    for material in state.get_materials(): material_names.append(material.resource_name)
    for expected in ["M_Door_Frame", "M_Door_Leaf", "M_Door_Recess_Seal", "M_Living_Accent", "M_Status_Red", "M_Status_Green"]:
        assert(expected in material_names, "Missing material: " + expected)
    print("GODOT_VALIDATION_OK: hierarchy, sockets, six materials, metre scale, leaf travel, inherited seals")
    print("Godot version: ", Engine.get_version_info().string)
    quit(0)
