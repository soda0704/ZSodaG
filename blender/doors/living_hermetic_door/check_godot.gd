extends SceneTree

func _initialize():
    var document = GLTFDocument.new()
    var state = GLTFState.new()
    var path = ProjectSettings.globalize_path("res://../../../assets/models/doors/living_hermetic_door/living_hermetic_door.glb")
    var error = document.append_from_file(path, state)
    assert(error == OK, "GLB failed to load")
    var model = document.generate_scene(state)
    root.add_child(model)
    await process_frame
    var assembly = model if model.name == "LivingHermeticDoor" else model.find_child("LivingHermeticDoor", true, false)
    assert(assembly != null, "Root missing")
    var names = ["Frame", "LeftLeaf", "RightLeaf", "FrontStatusLamps", "BackStatusLamps", "Socket_FrontAccessPanel", "Socket_BackAccessPanel"]
    for item in names:
        assert(assembly.get_node_or_null(NodePath(item)) != null, "Missing node: " + item)
    var left = assembly.get_node("LeftLeaf")
    var right = assembly.get_node("RightLeaf")
    var report = JSON.parse_string(FileAccess.get_file_as_string("res://prepared_validation.json"))
    for leaf in [left, right]:
        var origin = report.objects[String(leaf.name)].origin
        assert(leaf.position.is_equal_approx(Vector3(origin[0], origin[2], -origin[1])))
        assert(leaf.get_child_count() == 4, "Keep all four fastener groups on each leaf")
    assert(assembly.get_node("FrontStatusLamps").has_node("FrontStatusLenses"))
    assert(assembly.get_node("BackStatusLamps").has_node("BackStatusLenses"))
    assert(assembly.get_node("Socket_FrontAccessPanel").position.is_equal_approx(Vector3(1.720, 1.483, 0.2)))
    assert(assembly.get_node("Socket_BackAccessPanel").position.is_equal_approx(Vector3(-1.720, 1.483, -0.2)))
    var fastener = left.get_child(0)
    var initial_position = fastener.global_position
    left.position.x -= 1.255
    right.position.x += 1.255
    assert(fastener.global_position.is_equal_approx(initial_position + Vector3(-1.255, 0, 0)))
    assert(left.position.x + left.mesh.get_aabb().end.x < -1.2)
    assert(right.position.x + right.mesh.get_aabb().position.x > 1.2)
    var material_names = []
    for material in state.get_materials(): material_names.append(material.resource_name)
    for expected in ["M_Door_Frame", "M_Door_Leaf", "M_Door_Recess_Seal", "M_Living_Accent", "M_Status_Red", "M_Status_Green"]:
        assert(expected in material_names, "Missing material: " + expected)
    print("GODOT_VALIDATION_OK: user geometry, hierarchy, sockets, six materials, metre scale, leaf travel, inherited fasteners")
    print("Godot version: ", Engine.get_version_info().string)
    quit(0)
