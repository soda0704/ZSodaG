class_name WeaponController
extends Node3D

const TYPES := [&"pistol", &"m4a1", &"kitchen_knife"]
const CAPACITY := {&"pistol": 12, &"m4a1": 30, &"kitchen_knife": 0}
const TITLES := {&"pistol": "Пистолет", &"m4a1": "M4A1", &"kitchen_knife": "Кухонный нож"}
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

func _ready() -> void:
	_pose = Node3D.new()
	get_parent().head.add_child(_pose)
	_pose.position = _rest
	for id: StringName in TYPES:
		var model := (load("res://assets/models/weapons/%s.glb" % id) as PackedScene).instantiate()
		_pose.add_child(model)
		model.hide()
		_models[id] = model
	_flash = OmniLight3D.new()
	_pose.add_child(_flash)
	_flash.position = Vector3(0, 0.05, -0.55)
	_flash.light_color = Color(1.0, 0.65, 0.22)
	_flash.light_energy = 3.0
	_flash.omni_range = 5.0
	_flash.hide()
	_audio = AudioStreamPlayer3D.new()
	add_child(_audio)
	_audio.max_distance = 24.0
	_audio.volume_db = -24.0
	_audio.stream = _make_shot_sound()
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
	var active: bool = TYPES.has(kind) and not player.survival.dead and not player.is_sleeping_in_bunk()
	_pose.visible = active
	var local: bool = player.is_local_player()
	_hud.visible = active and local and not player._is_journal_open() and not get_node("/root/GameMenu").is_menu_open()
	if _hud.visible:
		var controller: bool = get_node("/root/SteamInput").using_controller
		_hud.text = str(TITLES[kind])
		if kind != &"kitchen_knife":
			var reserve := "патроны: %d" % pistol_ammo if kind == &"pistol" else "магазины: %d" % rifle_magazines.size()
			_hud.text += "  %d · %s\n%s" % [rounds, reserve, "Перезарядка…" if reload_left > 0.0 else ("[↑] Перезарядка" if controller else "[R] Перезарядка")]
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
	if not multiplayer.is_server() or player.survival.dead or player.is_sleeping_in_bunk() or not TYPES.has(kind):
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
		_play_effect.rpc(true)
		_notify_inventory()
		return true
	if action != &"fire" or _cooldown > 0.0 or reload_left > 0.0:
		return false
	if kind != &"kitchen_knife" and rounds <= 0:
		return false
	_cooldown = 0.1 if kind == &"m4a1" else 0.55 if kind == &"kitchen_knife" else 0.24
	if kind != &"kitchen_knife":
		rounds -= 1
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
			target.apply_impulse(direction * 2.0, hit.position - target.global_position)
		_impact.rpc(hit.position, hit.normal)
	_play_effect.rpc(false)
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
	if _animation != null and _animation.is_valid():
		_animation.kill()
	_pose.position = _rest
	_pose.rotation = Vector3.ZERO
	_flash.hide()

@rpc("authority", "call_local", "reliable", 2)
func _play_effect(reloading: bool) -> void:
	_cancel_animation()
	_animation = create_tween()
	if reloading:
		_animation.tween_property(_pose, "rotation", Vector3(-0.4, 0, -0.5), 0.2)
		_animation.tween_interval(1.6 if kind == &"m4a1" else 0.85)
		_animation.tween_property(_pose, "rotation", Vector3.ZERO, 0.3)
	elif kind == &"kitchen_knife":
		_animation.tween_property(_pose, "rotation", Vector3(0.4, -0.7, -0.9), 0.12)
		_animation.tween_property(_pose, "rotation", Vector3.ZERO, 0.3)
	else:
		_audio.pitch_scale = 0.8 if kind == &"m4a1" else 1.1
		_audio.play()
		_flash.show()
		_pose.position += Vector3(0, 0.014, 0.035)
		_pose.rotation.x = 0.07
		_animation.tween_interval(0.045)
		_animation.tween_callback(_flash.hide)
		_animation.tween_property(_pose, "position", _rest, 0.07)
		_animation.parallel().tween_property(_pose, "rotation", Vector3.ZERO, 0.07)

@rpc("authority", "call_local", "unreliable", 2)
func _impact(point: Vector3, normal: Vector3) -> void:
	var mark := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.015
	mesh.height = 0.03
	mark.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("edb870")
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mark.material_override = mat
	get_tree().current_scene.add_child(mark)
	# Decals are world-space evidence of a shot. In particular, they must not
	# inherit the moving elevator cabin's transform.
	mark.top_level = true
	mark.global_position = point + normal * 0.015
	var fade := mark.create_tween()
	fade.tween_interval(0.25)
	fade.tween_callback(mark.queue_free)

func _make_shot_sound() -> AudioStreamWAV:
	var bytes := PackedByteArray()
	var random := RandomNumberGenerator.new()
	random.seed = 742
	for index in 3600:
		var time := index / 22050.0
		var wave := (random.randf_range(-1.0, 1.0) * 0.7 + sin(time * 900.0) * 0.3) * exp(-time * 42.0)
		bytes.append(int(clampf(wave * 100.0 + 128.0, 0, 255)))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = 22050
	stream.data = bytes
	return stream
