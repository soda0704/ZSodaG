extends Node3D

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var elevator := get_node("ElevatorFunctionalBlockout")
	var camera := get_node("ReviewCamera") as Camera3D
	camera.current = true

	if elevator.get_node_or_null("CabinMoving/CabinVisualArt") == null:
		return _fail("CabinVisualArt is missing")
	var shaft_visual := elevator.get_node_or_null("Shaft/ShaftVisualArt")
	if shaft_visual == null or shaft_visual.get_child_count() != 11:
		return _fail("Expected 11 shaft art modules")
	for floor_index in 6:
		if elevator.get_node_or_null("Landings/Floor_%d/LandingPortalArt" % floor_index) == null:
			return _fail("Landing portal art is missing on floor %d" % floor_index)

	await _capture_view(
		camera,
		Vector3(-12, 4.8, 7.8),
		Vector3(-2.0, 2.5, 0),
		"res://elevator_art_integrated_surface.png"
	)
	await _capture_view(
		camera,
		Vector3(-1.8, 1.9, -1.7),
		Vector3(-1.35, 1.55, 2.65),
		"res://elevator_art_integrated_panel.png"
	)
	await _capture_view(
		camera,
		Vector3(0.5, 2.0, 0),
		Vector3(-3.0, 2.0, 0),
		"res://elevator_art_integrated_door.png"
	)
	var cabin_door := elevator.get_node("CabinMoving/CabinDoor")
	var landing_door := elevator.get_node("Landings/Floor_0/LandingDoor")
	var debug_file := FileAccess.open("res://door_state_debug.txt", FileAccess.WRITE)
	debug_file.store_line(
		"cabin is_open=%s position=%s scale=%s" % [
			cabin_door.is_open,
			cabin_door.get_node("DoorVisual").position,
			cabin_door.get_node("DoorVisual").scale,
		]
	)
	debug_file.store_line(
		"landing is_open=%s position=%s scale=%s" % [
			landing_door.is_open,
			landing_door.get_node("DoorVisual").position,
			landing_door.get_node("DoorVisual").scale,
		]
	)
	debug_file.close()
	cabin_door.visible = false
	await _capture_view(
		camera,
		Vector3(0.5, 2.0, 0),
		Vector3(-3.0, 2.0, 0),
		"res://elevator_art_door_without_cabin_door.png"
	)
	landing_door.visible = false
	await _capture_view(
		camera,
		Vector3(0.5, 2.0, 0),
		Vector3(-3.0, 2.0, 0),
		"res://elevator_art_door_without_both_doors.png"
	)
	cabin_door.visible = true
	landing_door.visible = true

	if not elevator.request_floor(5):
		return _fail("Request 0 -> -5 was rejected")
	if not await _wait_for_idle_floor(elevator, 5):
		return _fail("Elevator did not arrive at -5")
	if not elevator.request_floor(0):
		return _fail("Request -5 -> 0 was rejected")
	if not await _wait_for_idle_floor(elevator, 0):
		return _fail("Elevator did not return to 0")

	print("ART_INTEGRATION_ROUND_TRIP PASS 0 -> -5 -> 0")
	get_tree().quit()


func _wait_for_idle_floor(elevator: Node, floor_index: int) -> bool:
	for _frame in 1200:
		if elevator.current_floor_index == floor_index and elevator.state == 1:
			return true
		await get_tree().process_frame
	return false


func _capture_view(
	camera: Camera3D,
	position: Vector3,
	target: Vector3,
	path: String
) -> void:
	camera.look_at_from_position(position, target)
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)


func _fail(message: String) -> void:
	push_error("ART_INTEGRATION_TEST FAIL: %s" % message)
	get_tree().quit(1)
