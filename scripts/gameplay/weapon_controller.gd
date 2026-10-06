class_name WeaponController
extends Node3D

const TYPES := [&"pistol", &"m4a1", &"kitchen_knife"]
const CAPACITY := {&"pistol": 12, &"m4a1": 30, &"kitchen_knife": 0}
const TITLES := {&"pistol": "Пистолет", &"m4a1": "M4A1", &"kitchen_knife": "Кухонный нож"}
@export var pistol_sound: AudioStream
@export var rifle_sound: AudioStream
@export var pistol_reload_sound: AudioStream
@export var rifle_reload_sound: AudioStream
@export var pistol_empty_sound: AudioStream
@export var rifle_empty_sound: AudioStream
@export var concrete_impact_sound: AudioStream
@export var metal_impact_sound: AudioStream
@export var snow_impact_sound: AudioStream
@onready var _mechanism_audio: AudioStreamPlayer3D = $MechanismAudio
@export var impact_audio_scene: PackedScene

var kind: StringName = &""
var rounds: int = 0
var pistol_ammo: int = 0
var rifle_magazines: Array[int] = []
var reload_left: float = 0.0
var _reload_kind: StringName = &""
var _cooldown: float = 0.0
var _models: Dictionary = {}
var _pose: Node3D
var _hud: Label
var _flash: OmniLight3D
var _audio: AudioStreamPlayer3D
var _animation: Tween
var _rest := Vector3(0.2, -0.18, -0.4)
var _mounted_lamp: Node3D
var _mounted_beam: SpotLight3D

func _ready() -> void:
	_pose = Node3D.new()
	get_parent().head.add_child(_pose)
	_pose.position = _rest
	_mounted_lamp = preload("res://scripts/gameplay/tool_models.gd").build_mount()
	_pose.add_child(_mounted_lamp)
	_mounted_lamp.position = Vector3(0.075, 0.01, -0.16)
	_mounted_beam = SpotLight3D.new()
	_mounted_lamp.add_child(_mounted_beam)
	_mounted_beam.position.z = -0.095
	_mounted_beam.spot_range = 25.0
	_mounted_beam.spot_angle = 32.0
	_mounted_beam.light_energy = 3.0
	_mounted_beam.light_color = Color("fff0ce")
	_mounted_beam.shadow_enabled = true
	_mounted_beam.light_cull_mask = 0xFFFFF
	_mounted_beam.shadow_caster_mask = 0xFFFFF ^ (1 << 19)
	for mesh in _mounted_lamp.find_children("*", "MeshInstance3D", true, false):
		mesh.layers = 1 << 19
	for id: StringName in TYPES:
		var model := (load("res://assets/models/weapons/%s.glb" % id) as PackedScene).instantiate()
		_pose.add_child(model)
		for mesh in model.find_children("*", "MeshInstance3D", true, false):
			mesh.layers = 1 << 19
		model.hide()
		_models[id] = model
	_flash = OmniLight3D.new()
	_pose.add_child(_flash)
	_flash.position = Vector3(0, 0.05, -0.55)
	_flash.light_color = Color(1.0, 0.65, 0.22)
	_flash.light_energy = 3.0
	_flash.omni_range = 5.0
	_flash.hide()
	_audio = $ShotAudio
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	layer.add_child(_hud)
	_hud.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_hud.offset_left = -360
	_hud.offset_top = -100
	_hud.offset_right = -30
	_hud.offset_bottom = -20
	_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hud.add_theme_font_size_override("font_size", 22)
	if not InputMap.has_action("weapon_attack"):
		InputMap.add_action("weapon_attack", 0.25)
		var mouse := InputEventMouseButton.new()
		mouse.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("weapon_attack", mouse)
		var trigger := InputEventJoypadMotion.new()
		trigger.axis = JOY_AXIS_TRIGGER_RIGHT
		trigger.axis_value = 1.0
		InputMap.action_add_event("weapon_attack", trigger)

func apply_state(id: StringName, ammo: int, remaining: float) -> void:
	if kind != id:
		_rest = Vector3(0.18, -0.20, -0.60) if id == &"m4a1" else Vector3(0.18, -0.16, -0.34)
		_cancel_animation()
		kind = id
		_pose.position = _rest + Vector3(0, -0.25, 0)
		_animation = create_tween()
		_animation.tween_property(_pose, "position", _rest, 0.25).set_trans(Tween.TRANS_CUBIC)
	rounds = clampi(ammo, 0, int(CAPACITY.get(id, 0)))
	reload_left = remaining
	for model_id in _models:
		_models[model_id].visible = id == model_id

func _physics_process(delta: float) -> void:
	var player := get_parent()
	if multiplayer.is_server():
		_cooldown = maxf(0.0, _cooldown - delta)
		if reload_left > 0.0:
			if player.survival.dead or player.is_sleeping_in_bunk() or kind != _reload_kind:
				reload_left = 0.0
				_cancel_animation()
			else:
				reload_left = maxf(0.0, reload_left - delta)
				if reload_left == 0.0:
					_commit_reload()
					_notify_inventory()
	var active: bool = TYPES.has(kind) and not player.survival.dead and not player.is_sleeping_in_bunk() and not player.is_driving()
	_pose.visible = active
	_mounted_lamp.visible = active and player.weapon_light_mounted
	_mounted_beam.visible = _mounted_lamp.visible and player._flashlight_enabled and player._battery_charge > 0.0
	var local: bool = player.is_local_player()
	_hud.visible = active and local and not player._is_journal_open() and not get_node("/root/GameMenu").is_menu_open()
	if _hud.visible:
		var controller: bool = get_node("/root/SteamInput").using_controller
		_hud.text = str(TITLES[kind])
		if kind != &"kitchen_knife":
			var reserve := "патроны: %d" % pistol_ammo if kind == &"pistol" else "магазины: %d" % rifle_magazines.size()
			var action_hint := "[↑] Перезарядка" if controller else "[R] Перезарядка"
			if player.weapon_light_mounted and player._battery_charge <= 0.0 and not player._spare_batteries.is_empty():
				action_hint = "[↑] Заменить батарейку" if controller else "[R] Заменить батарейку"
			_hud.text += "  %d · %s\n%s" % [rounds, reserve, "Перезарядка…" if reload_left > 0.0 else ""]
		else:
			_hud.text += "\n" + ("[R2] Удар" if controller else "[ЛКМ] Удар")
	if active and local and _hud.visible and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var attack := Input.is_action_pressed("weapon_attack") if kind == &"m4a1" else Input.is_action_just_pressed("weapon_attack")
		if attack and _cooldown <= 0.0 and reload_left <= 0.0:
			request_action(&"fire")
			if not multiplayer.is_server():
				_cooldown = 0.1 if kind == &"m4a1" else 0.24
	if not multiplayer.is_server():
		_cooldown = maxf(0.0, _cooldown - delta)

func request_action(action: StringName) -> void:
	if not get_parent().is_local_player():
		return
	if multiplayer.is_server():
		perform_action(action)
	else:
		_request.rpc_id(1, action)

@rpc("any_peer", "call_remote", "reliable", 0)
func _request(action: StringName) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == get_parent().owner_peer_id:
		perform_action(action)

func perform_action(action: StringName) -> bool:
	var player := get_parent()
	if player.is_driving():
		return false
	if not multiplayer.is_server() or player.survival.dead or player.is_sleeping_in_bunk() or not TYPES.has(kind):
		return false
	if player._battery_action_busy:
		return false
	if action == &"reload":
		if kind == &"kitchen_knife" or reload_left > 0.0 or rounds >= CAPACITY[kind]:
			return false
		if kind == &"pistol" and pistol_ammo <= 0:
			return false
		if kind == &"m4a1" and (rifle_magazines.is_empty() or int(rifle_magazines.max()) <= rounds):
			return false
		reload_left = 2.1 if kind == &"m4a1" else 1.35
		_reload_kind = kind
		_play_effect.rpc(true, kind)
		_notify_inventory()
		return true
	if action != &"fire" or _cooldown > 0.0 or reload_left > 0.0:
		return false
	if kind != &"kitchen_knife" and rounds <= 0:
		_cooldown = 0.35
		_play_empty.rpc(kind)
		return false
	_cooldown = 0.1 if kind == &"m4a1" else 0.55 if kind == &"kitchen_knife" else 0.24
	if kind != &"kitchen_knife":
		rounds -= 1
		preload("res://scripts/gameplay/gameplay_noise.gd").emit(player, 32.0 if kind == &"m4a1" else 26.0)
	var origin: Vector3 = player.head.global_position
	var direction: Vector3 = -player.head.global_basis.z
	var reach := 2.0 if kind == &"kitchen_knife" else 120.0
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * reach, 7, [player.get_rid()])
	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var target: Node = hit.collider
		if target.has_method("apply_weapon_damage"):
			target.apply_weapon_damage(50.0 if kind == &"kitchen_knife" else 25.0 if kind == &"m4a1" else 35.0)
		if target is RigidBody3D:
			if target.has_method("release_elevator_cargo"):
				target.release_elevator_cargo()
			target.apply_impulse(direction * 2.0, hit.position - target.global_position)
		var surface := target as Node3D
		if surface != null:
			var impact_surface := &"" if kind == &"kitchen_knife" or target.has_method("apply_weapon_damage") else ContactSurface.classify(target, true)
			_impact.rpc(hit.position, hit.normal, surface.get_path(), surface.to_local(hit.position + hit.normal * 0.015), impact_surface)
	_play_effect.rpc(false, kind)
	_notify_inventory()
	return true

func _notify_inventory() -> void:
	var player := get_parent()
	player._inventory_revision += 1
	# Periodic checkpoint saving handles ammo; avoid disk writes per bullet.
	player._receive_equipment.rpc(player.get_inventory_snapshot())

func _commit_reload() -> void:
	if kind == &"pistol":
		var inserted := mini(12 - rounds, pistol_ammo)
		rounds += inserted
		pistol_ammo -= inserted
	elif kind == &"m4a1" and not rifle_magazines.is_empty():
		var fullest: int = rifle_magazines.max()
		if fullest <= rounds:
			return
		rifle_magazines.erase(fullest)
		if rounds > 0:
			rifle_magazines.append(rounds)
		rounds = fullest

func _cancel_animation() -> void:
	_mechanism_audio.stop()
	if _animation != null and _animation.is_valid():
		_animation.kill()
	_pose.position = _rest
	_pose.rotation = Vector3.ZERO
	_flash.hide()

func play_mounted_battery_action() -> void:
	_cancel_animation()
	_animation = create_tween()
	_animation.tween_property(_pose, "rotation", Vector3(-0.15, 0.0, -0.35), 0.25)
	_animation.tween_interval(0.47)
	_animation.tween_property(_pose, "rotation", Vector3.ZERO, 0.38)

@rpc("authority", "call_local", "reliable", 2)
func _play_effect(reloading: bool, effect_kind: StringName = &"") -> void:
	if effect_kind.is_empty():
		effect_kind = kind
	_cancel_animation()
	_animation = create_tween()
	if reloading:
		_mechanism_audio.stream = rifle_reload_sound if effect_kind == &"m4a1" else pistol_reload_sound
		_mechanism_audio.play()
		_animation.tween_property(_pose, "rotation", Vector3(-0.4, 0, -0.5), 0.2)
		_animation.tween_interval(1.6 if effect_kind == &"m4a1" else 0.85)
		_animation.tween_property(_pose, "rotation", Vector3.ZERO, 0.3)
	elif effect_kind == &"kitchen_knife":
		_animation.tween_property(_pose, "rotation", Vector3(0.4, -0.7, -0.9), 0.12)
		_animation.tween_property(_pose, "rotation", Vector3.ZERO, 0.3)
	else:
		var shot := rifle_sound if effect_kind == &"m4a1" else pistol_sound
		if shot != null:
			if _audio.stream != shot:
				_audio.stream = shot
			_audio.pitch_scale = 1.0
			_audio.play()
		_flash.show()
		_pose.position += Vector3(0, 0.014, 0.035)
		_pose.rotation.x = 0.07
		_animation.tween_interval(0.045)
		_animation.tween_callback(_flash.hide)
		_animation.tween_property(_pose, "position", _rest, 0.07)
		_animation.parallel().tween_property(_pose, "rotation", Vector3.ZERO, 0.07)

@rpc("authority", "call_local", "unreliable", 2)
func _impact(point: Vector3, normal: Vector3, surface_path: NodePath = NodePath(), local_point: Vector3 = Vector3.ZERO, impact_surface: StringName = &"") -> void:
	if not impact_surface.is_empty() and impact_audio_scene != null:
		var impact_audio := impact_audio_scene.instantiate() as AudioStreamPlayer3D
		get_tree().root.add_child(impact_audio)
		impact_audio.global_position = point
		impact_audio.stream = metal_impact_sound if impact_surface == &"metal" else snow_impact_sound if impact_surface == &"snow" else concrete_impact_sound
		impact_audio.finished.connect(impact_audio.queue_free)
		impact_audio.play()
	var surface := get_node_or_null(surface_path) as Node3D if not surface_path.is_empty() else null
	if not surface_path.is_empty() and surface == null:
		return
	var mark := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.015
	mesh.height = 0.03
	mark.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("edb870")
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mark.material_override = mat
	mark.add_to_group("weapon_impacts")
	if surface != null:
		surface.add_child(mark)
		mark.position = local_point
	else:
		get_tree().current_scene.add_child(mark)
		mark.global_position = point + normal * 0.015
	var fade := mark.create_tween()
	fade.tween_interval(0.25)
	fade.tween_callback(mark.queue_free)

@rpc("authority", "call_local", "reliable", 2)
func _play_empty(effect_kind: StringName) -> void:
	_mechanism_audio.stream = rifle_empty_sound if effect_kind == &"m4a1" else pistol_empty_sound
	_mechanism_audio.play()
