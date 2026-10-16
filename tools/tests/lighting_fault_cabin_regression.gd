extends SceneTree
## Snapshot-only electrical faults and the production moving cabin light.

class PreviewLighting extends WorldLighting:
	func _ready() -> void:
		set_process(false)

var failures := 0
var power_signals := 0

func _initialize() -> void:
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, "res://tools/.local/base-surface-review/unused_test_save.cfg")
	call_deferred("run")

func check(value: bool, label: String) -> void:
	print("PASS " if value else "FAIL ", label)
	if not value:
		failures += 1

func run() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var state := BaseGameplayController.new()
	state.name = "BaseGameplayController"
	state.progress_persistence_enabled = false
	holder.add_child(state)
	state.set_process(false)
	state.power_state_changed.connect(func(_powered: bool) -> void: power_signals += 1)
	var lights := Node3D.new()
	lights.name = "WorldLighting"
	holder.add_child(lights)
	for circuit_name in ["Standard", "Emergency"]:
		var circuit := Node3D.new()
		circuit.name = circuit_name
		lights.add_child(circuit)
		circuit.add_child(SpotLight3D.new())
	var power := BasePowerLightingController.new()
	holder.add_child(power)
	var snapshot := state.get_snapshot()
	snapshot.fuel_delivered = true
	snapshot.fuel_liters = 20.0
	snapshot.main_breaker_on = true
	snapshot.containment = {}
	state._apply_snapshot(snapshot, false, false)
	check(power.is_standard_powered and lights.get_node("Standard").visible and not lights.get_node("Emergency").visible, "normal power selects the standard circuit")
	var signals_before_fault := power_signals
	snapshot.containment = {"fault": true}
	state._apply_snapshot(snapshot, false, false)
	check(state.main_breaker_on and power_signals == signals_before_fault, "fault arrives without changing the breaker or power signal")
	check(not power.is_standard_powered and not lights.get_node("Standard").visible and lights.get_node("Emergency").visible, "snapshot-only fault extinguishes standard lights and enables emergency lights")
	snapshot.main_breaker_on = false
	state._apply_snapshot(snapshot, false, false)
	check(not power.is_standard_powered, "switching breaker off during reset keeps standard lights off")
	snapshot.main_breaker_on = true
	snapshot.containment = {"fault": false, "resolved": true}
	state._apply_snapshot(snapshot, false, false)
	check(power.is_standard_powered and not lights.get_node("Emergency").visible, "reset restores the standard circuit")
	snapshot.containment = {"fault": true}
	state._apply_snapshot(snapshot, true, false)
	check(not power.is_standard_powered, "initial or restored fault snapshot starts in emergency lighting")
	holder.queue_free()
	await process_frame

	var preview := PreviewLighting.new()
	root.add_child(preview)
	var authored: Dictionary = {}
	for index in 10:
		var lamp := SpotLight3D.new()
		lamp.position = Vector3(index, 2, 0)
		lamp.light_energy = 1.0 + index * 0.1
		preview.add_child(lamp)
		authored[lamp] = lamp.light_energy
	preview._update_editor_lamp_visibility(Vector3.ZERO)
	var active := 0
	var preserved := true
	for lamp in authored:
		if preview._editor_visibility.get(lamp, false): active += 1
		preserved = preserved and is_equal_approx(lamp.light_energy, authored[lamp]) and lamp.visible
	check(active == WorldLighting.MAX_ACTIVE_LAMPS and preserved, "editor preview uses instance RIDs and preserves authored energy and visibility")
	var added := SpotLight3D.new()
	added.position = Vector3(0, 1, 0)
	preview.add_child(added)
	preview._update_editor_lamp_visibility(Vector3.ZERO)
	check(preview._editor_visibility.get(added, false), "editor preview discovers newly added lamps")
	preview.remove_child(added)
	preview._update_editor_lamp_visibility(Vector3.ZERO)
	check(not preview._editor_visibility.has(added), "removed lamps leave the preview pool")
	added.free()
	var deleted: SpotLight3D = preview._editor_lights.back()
	deleted.free()
	preview._update_editor_lamp_visibility(Vector3.ZERO)
	check(preview._editor_visibility.size() == 9 and preview._editor_lights.size() == 9, "deleted lamps release their preview state")
	preview.queue_free()
	await process_frame

	var packed: PackedScene = load("res://scenes/objects/elevator/elevator_functional_blockout.tscn")
	var elevator: FunctionalElevatorController = packed.instantiate()
	elevator.require_all_connected_players = false
	elevator.unlocked_floor_index = 1
	elevator.travel_speed = 45.0
	elevator.travel_start_stop_time = 0.05
	elevator.door_animation_duration = 0.05
	elevator.arrival_alignment_duration = 0.05
	root.add_child(elevator)
	var lamp := elevator.cabin_light
	check(lamp.get_parent() == elevator.cabin and lamp.shadow_enabled and lamp.visible, "authored cabin light belongs to the moving body and casts shadows")
	var sampler := PreviewLighting.new()
	root.add_child(sampler)
	var view_camera := Camera3D.new()
	elevator.cabin.add_child(view_camera)
	view_camera.position = Vector3(0, 1.65, 0)
	await physics_frame
	var lit_hands := sampler.sample_view_light(view_camera)
	elevator.set_powered(false)
	check(not lamp.visible and not elevator._cabin_light_materials[0].emission_enabled, "cabin source and lenses turn off with elevator power")
	var dark_hands := sampler.sample_view_light(view_camera)
	check(lit_hands.r > dark_hands.r + 0.01, "moving cabin source contributes to first-person hand lighting")
	elevator.set_powered(true)
	check(lamp.visible and elevator._cabin_light_materials[0].emission_enabled, "cabin source and lenses restore with elevator power")
	var local_position := lamp.position
	var start_y := lamp.global_position.y
	check(elevator.request_call(1), "unoccupied powered cabin accepts a lower-floor call")
	var deadline := Time.get_ticks_msec() + 8000
	var moved := false
	var follows := true
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		follows = follows and lamp.position.is_equal_approx(local_position) and lamp.global_position.is_equal_approx(elevator.cabin.to_global(local_position))
		moved = moved or lamp.global_position.y < start_y - 5.0
		if elevator.current_floor_index == 1 and elevator.state == elevator.ElevatorState.IDLE_OPEN:
			break
	check(moved and follows and elevator.current_floor_index == 1, "light travels down with the real cabin throughout the trip")
	var replica: FunctionalElevatorController = packed.instantiate()
	replica.position.x = 100.0
	root.add_child(replica)
	elevator.set_powered(false)
	replica._apply_network_snapshot(elevator.get_network_snapshot())
	check(not replica.cabin_light.visible and not replica._cabin_light_materials[0].emission_enabled, "replicated power state disables client cabin light")
	elevator.set_powered(true)
	replica._apply_network_snapshot(elevator.get_network_snapshot())
	check(replica.cabin_light.visible, "replicated power restoration enables client cabin light")
	elevator.queue_free()
	replica.queue_free()
	sampler.queue_free()
	await process_frame
	print("RESULT FAILURES ", failures)
	quit(1 if failures else 0)
