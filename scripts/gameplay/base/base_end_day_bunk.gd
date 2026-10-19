class_name BaseEndDayBunk
extends StaticBody3D

const MAX_NAME_TAG_CHARACTERS := 14

@export_range(0, 1, 1) var assigned_player_slot: int = 0

@onready var indicator: MeshInstance3D = %Indicator
@onready var status_label: Label3D = %StatusLabel
@onready var name_tag_label: Label3D = %NameTagLabel
@onready var bed_pivot: Node3D = %BedPivot
@onready var sleep_surface_collision: CollisionShape3D = (
	%SleepSurface.get_node("CollisionShape3D") as CollisionShape3D
)
@onready var sleep_pose: Marker3D = %SleepPose
@onready var wake_pose: Marker3D = %WakePose

var _controller: BaseGameplayController
var _indicator_material: StandardMaterial3D
func _ready() -> void:
	status_label.hide()
	add_to_group("end_day_bunks")
	_indicator_material = (
		indicator.get_active_material(0).duplicate() as StandardMaterial3D
	)
	indicator.material_override = _indicator_material
	call_deferred("_bind_controller")


func get_interaction_prompt() -> String:
	var controller := _get_controller()
	if controller == null or not controller.can_end_current_day():
		return "Вы не можете сейчас спать, необходимо завершить все задачи"
	if controller.get_player_slot(multiplayer.get_unique_id()) != assigned_player_slot: return ""
	return "Лечь спать"

func get_sleep_interaction_prompt() -> String:
	return get_interaction_prompt()


func interact(interactor: Node) -> void:
	network_interact(multiplayer.get_unique_id(), interactor)


func network_interact(peer_id: int, interactor: Node) -> void:
	network_sleep_interact(peer_id, interactor)

func network_sleep_interact(peer_id: int, interactor: Node) -> void:
	if not multiplayer.is_server() or not interactor is GamePlayer or interactor.owner_peer_id != peer_id or interactor.survival.dead or interactor.is_carrying_corpse() or interactor.is_driving(): return
	var controller := _get_controller()
	if controller == null or controller.get_player_node(peer_id) != interactor or controller.get_player_slot(peer_id) != assigned_player_slot or controller.is_peer_sleeping(peer_id) or not controller.can_end_current_day(): return
	if interactor.global_position.distance_to(global_position) > 3.0: return
	if not controller.set_end_day_ready_authoritative(peer_id, true): return
	if controller.set_peer_sleeping_authoritative(peer_id, true): interactor.enter_bunk_sleep_authoritative(sleep_pose.global_transform)


func cancel_sleep_authoritative(peer_id: int, interactor: Node) -> bool:
	var controller := _get_controller()
	if (
		not multiplayer.is_server()
		or interactor == null
		or (interactor is GamePlayer and interactor.is_carrying_corpse())
		or int(interactor.get("owner_peer_id")) != peer_id
		or controller == null
		or controller.get_player_slot(peer_id) != assigned_player_slot
		or not controller.is_peer_sleeping(peer_id)
	):
		return false
	# Move clear before restoring the bed collision and cancelling the sleep vote.
	if interactor.has_method("leave_bunk_sleep_authoritative"):
		interactor.call("leave_bunk_sleep_authoritative", wake_pose.global_transform)
	controller.set_peer_sleeping_authoritative(peer_id, false)
	controller.set_end_day_ready_authoritative(peer_id, false)
	return true


func _bind_controller() -> void:
	_controller = _get_controller()
	if _controller == null:
		push_warning("BaseEndDayBunk could not find BaseGameplayController")
		_refresh_visuals()
		return
	if not _controller.snapshot_changed.is_connected(_on_snapshot_changed):
		_controller.snapshot_changed.connect(_on_snapshot_changed)
	_refresh_visuals()


func _get_controller() -> BaseGameplayController:
	if is_instance_valid(_controller):
		return _controller
	_controller = get_tree().get_first_node_in_group(
		"base_gameplay_controller"
	) as BaseGameplayController
	return _controller


func _on_snapshot_changed(_snapshot: Dictionary) -> void:
	_refresh_visuals()


func _refresh_visuals() -> void:
	var controller := _get_controller()
	var assigned_peer_id := (
		controller.get_peer_for_player_slot(assigned_player_slot)
		if controller != null
		else 0
	)
	var is_available := (
		controller != null
		and controller.phase in [
			BaseGameplayController.BasePhase.ACTIVE_DAY,
			BaseGameplayController.BasePhase.ENDING_DAY,
		]
		and assigned_peer_id > 0
	)
	var is_ready := (
		is_available
		and controller.is_peer_ready_to_end_day(assigned_peer_id)
	)
	var is_sleeping := (
		is_ready and controller.is_peer_sleeping(assigned_peer_id)
	)
	bed_pivot.rotation.x = 0.0
	sleep_surface_collision.set_deferred("disabled", is_sleeping)

	var color := Color(0.22, 0.25, 0.28, 1.0)
	if is_sleeping:
		color = Color(0.18, 0.48, 1.0, 1.0)
	elif is_ready:
		color = Color(0.08, 0.95, 0.24, 1.0)
	elif is_available:
		color = Color(1.0, 0.55, 0.04, 1.0)
	_indicator_material.albedo_color = color.darkened(0.4)
	_indicator_material.set_meta("world_lighting_emission", true)
	_indicator_material.emission_enabled = true
	_indicator_material.emission = color
	_indicator_material.emission_energy_multiplier = 0.35

	var player_number := assigned_player_slot + 1
	if assigned_peer_id <= 0:
		status_label.text = "ИГРОК %d: СВОБОДНО" % player_number
		name_tag_label.text = "—"
		name_tag_label.set_meta("full_player_name", "")
	elif not is_available:
		status_label.text = "ИГРОК %d: НЕДОСТУПНО" % player_number
	elif is_sleeping:
		status_label.text = "ИГРОК %d: СПИТ" % player_number
	elif is_ready:
		status_label.text = "ИГРОК %d: ГОТОВ — ЛОЖИТЕСЬ" % player_number
	else:
		status_label.text = "ИГРОК %d: ОЖИДАНИЕ" % player_number
	if assigned_peer_id > 0:
		var full_name := controller.get_player_display_name(assigned_peer_id)
		name_tag_label.text = abbreviate_player_name(full_name)
		var font := ThemeDB.fallback_font
		var width := font.get_string_size(name_tag_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, name_tag_label.font_size).x
		name_tag_label.pixel_size = minf(0.005, 0.48 / maxf(1.0, width))
		name_tag_label.set_meta("full_player_name", full_name)


func abbreviate_player_name(player_name: String) -> String:
	var normalized := player_name.strip_edges()
	if normalized.is_empty():
		return "Без имени"
	if normalized.length() <= MAX_NAME_TAG_CHARACTERS:
		return normalized
	return normalized.left(MAX_NAME_TAG_CHARACTERS - 1).rstrip(" .") + "…"

func get_interaction_hint_for(_interactor: Node) -> String:
	var message := get_interaction_prompt()
	var controller := _get_controller()
	if message.is_empty() or controller == null or not controller.can_end_current_day(): return message
	return get_node("/root/SteamInput").get_action_hint(&"interact") + " " + message
