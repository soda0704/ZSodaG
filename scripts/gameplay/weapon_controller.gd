class_name WeaponController
extends Node3D

const TYPES := [&"pistol", &"m4a1", &"kitchen_knife"]
const MODEL_SCENES := {
	&"pistol": preload("res://scenes/objects/items/pistol_model.tscn"),
	&"m4a1": preload("res://scenes/objects/items/m4a1_model.tscn"),
	&"kitchen_knife": preload("res://assets/models/weapons/kitchen_knife.glb"),
	&"pistol_ammo": preload("res://assets/models/weapons/pistol_ammo.glb"),
	&"rifle_magazine": preload("res://assets/models/weapons/rifle_magazine.glb"),
}
const CAPACITY := {&"pistol": 12, &"m4a1": 30, &"kitchen_knife": 0}
const TITLES := {&"pistol": "Пистолет", &"m4a1": "M4A1", &"kitchen_knife": "Кухонный нож"}
@export_group("Pistol balance")
@export_range(0.0, 500.0) var pistol_damage := 35.0
@export_range(0.03, 5.0) var pistol_fire_interval := 0.24
@export_range(0.1, 10.0) var pistol_reload_seconds := 1.35
@export_range(1.0, 500.0) var pistol_range := 120.0
@export_range(0.0, 100.0) var pistol_noise_radius := 26.0
@export_group("M4A1 balance")
@export_range(0.0, 500.0) var rifle_damage := 25.0
@export_range(0.03, 5.0) var rifle_fire_interval := 0.1
@export_range(0.1, 10.0) var rifle_reload_seconds := 2.1
@export_range(1.0, 500.0) var rifle_range := 120.0
@export_range(0.0, 100.0) var rifle_noise_radius := 32.0
@export_group("Knife balance")
@export_range(0.0, 500.0) var knife_damage := 50.0
@export_range(0.05, 5.0) var knife_attack_interval := 0.55
@export_range(0.1, 5.0) var knife_range := 2.0
@export_group("Audio")
@export var pistol_sound: AudioStream
@export var rifle_sound: AudioStream
@export var pistol_reload_sound: AudioStream
@export var rifle_reload_sound: AudioStream
@export var pistol_empty_sound: AudioStream
@export var rifle_empty_sound: AudioStream
@export var concrete_impact_sound: AudioStream
@export var metal_impact_sound: AudioStream
@export var snow_impact_sound: AudioStream
@export var glass_impact_sound: AudioStream
@export_group("Bullet marks")
@export var surface_mark_scene: PackedScene
@export var metal_mark_textures: Array[Texture2D] = []
@export var concrete_mark_textures: Array[Texture2D] = []
@export var glass_mark_textures: Array[Texture2D] = []
@export var snow_mark_textures: Array[Texture2D] = []
@export_range(0.01, 0.5) var metal_mark_size := 0.045
@export_range(0.01, 0.5) var concrete_mark_size := 0.07
@export_range(0.01, 0.5) var glass_mark_size := 0.23
@export_range(0.01, 0.5) var snow_mark_size := 0.12
@export_range(1.0, 600.0) var mark_lifetime := 90.0
@export_range(0.1, 20.0) var mark_fade_seconds := 5.0
@export_range(1, 512) var max_surface_marks := 128
@export_range(0.0005, 0.02) var mark_surface_offset := 0.003
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
var _mounted_lamp: Node3D
var _mounted_beam: SpotLight3D

func _ready() -> void:
	_pose = get_parent().body_animator.equipment_root()
	_mounted_lamp = _pose.get_node("MountedLamp")
	_mounted_beam = _mounted_lamp.get_node("Beam")
	for id: StringName in TYPES:
		_models[id] = _pose.get_node(String(id))
	_flash = _pose.get_node("MuzzleFlash")
	_audio = $ShotAudio
	_hud = $HUD/WeaponLabel
	$MuzzleTimer.timeout.connect(_flash.hide)

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
		_cancel_animation()
		kind = id

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
	var presentation_active: bool = active and player._journal_phase == 0
	for model_id in _models: _models[model_id].visible = presentation_active and model_id == kind
	_mounted_lamp.visible = presentation_active and player.weapon_light_mounted
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
				_cooldown = rifle_fire_interval if kind == &"m4a1" else pistol_fire_interval
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
	if player.is_driving() or player.is_carrying_corpse():
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
		reload_left = rifle_reload_seconds if kind == &"m4a1" else pistol_reload_seconds
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
	_cooldown = rifle_fire_interval if kind == &"m4a1" else knife_attack_interval if kind == &"kitchen_knife" else pistol_fire_interval
	if kind != &"kitchen_knife":
		rounds -= 1
		preload("res://scripts/gameplay/gameplay_noise.gd").emit(player, rifle_noise_radius if kind == &"m4a1" else pistol_noise_radius)
	var origin: Vector3 = player.head.global_position
	var direction: Vector3 = -player.head.global_basis.z
	var reach := knife_range if kind == &"kitchen_knife" else rifle_range if kind == &"m4a1" else pistol_range
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * reach, 23, [player.get_rid()])
	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.collider.has_method("resolve_bullet_hit"):
		hit = hit.collider.resolve_bullet_hit(origin,origin+direction*reach,hit)
	if not hit.is_empty():
		var target: Node = hit.collider
		if target.has_method("apply_weapon_damage"):
			target.apply_weapon_damage(knife_damage if kind == &"kitchen_knife" else rifle_damage if kind == &"m4a1" else pistol_damage)
		if target is RigidBody3D:
			if target.has_method("release_elevator_cargo"):
				target.release_elevator_cargo()
			target.apply_impulse(direction * 2.0, hit.position - target.global_position)
		var surface := target as Node3D
		if surface != null:
			var impact_surface := &"" if kind == &"kitchen_knife" or target.has_method("apply_weapon_damage") else ContactSurface.classify(target, true)
			_impact.rpc(hit.position, hit.normal, surface.get_path(), surface.to_local(hit.position), impact_surface, surface.global_basis.inverse()*hit.normal)
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
	get_parent().body_animator.cancel_weapon_action()
	_flash.hide()

func play_mounted_battery_action() -> void:
	_cancel_animation()
	get_parent().body_animator.weapon_battery_action(kind)

@rpc("authority", "call_local", "reliable", 2)
func _play_effect(reloading: bool, effect_kind: StringName = &"") -> void:
	if effect_kind.is_empty():
		effect_kind = kind
	get_parent().body_animator.weapon_effect(effect_kind,reloading)
	if reloading:
		_mechanism_audio.stream = rifle_reload_sound if effect_kind == &"m4a1" else pistol_reload_sound
		_mechanism_audio.play()
	elif effect_kind != &"kitchen_knife":
		var shot := rifle_sound if effect_kind == &"m4a1" else pistol_sound
		if shot != null:
			_audio.stream = shot
			_audio.pitch_scale = 1.0
			_audio.play()
		var muzzle: Marker3D = _models[effect_kind].get_node_or_null("Muzzle")
		if muzzle != null: _flash.global_transform = muzzle.global_transform
		_flash.show()
		$MuzzleTimer.start()

@rpc("authority", "call_local", "unreliable", 2)
func _impact(point: Vector3, normal: Vector3, surface_path: NodePath = NodePath(), local_point: Vector3 = Vector3.ZERO, impact_surface: StringName = &"", local_normal:Vector3 = Vector3.ZERO) -> void:
	if impact_surface.is_empty(): return
	if impact_audio_scene != null:
		var impact_audio := impact_audio_scene.instantiate() as AudioStreamPlayer3D
		get_tree().root.add_child(impact_audio)
		impact_audio.global_position = point
		impact_audio.stream = glass_impact_sound if impact_surface == &"glass" else metal_impact_sound if impact_surface == &"metal" else snow_impact_sound if impact_surface == &"snow" else concrete_impact_sound
		impact_audio.finished.connect(impact_audio.queue_free)
		impact_audio.play()
	var textures:Array[Texture2D] = glass_mark_textures if impact_surface == &"glass" else metal_mark_textures if impact_surface == &"metal" else snow_mark_textures if impact_surface == &"snow" else concrete_mark_textures
	if textures.is_empty() or surface_mark_scene == null: return
	var surface := get_node_or_null(surface_path) as Node3D if not surface_path.is_empty() else null
	if not surface_path.is_empty() and surface == null: return
	var parent:Node=get_tree().get_first_node_in_group("expedition_level") if surface==null else surface
	if parent==null: parent=get_tree().current_scene
	if parent==null: return
	var marks:=get_tree().get_nodes_in_group("weapon_impacts")
	var living:=marks.filter(func(node): return not node.is_queued_for_deletion())
	living.sort_custom(func(a,b): return a.created_usec<b.created_usec)
	while living.size()>=max_surface_marks:
		living.pop_front().queue_free()
	var mark:Node3D=surface_mark_scene.instantiate()
	parent.add_child(mark)
	var facing:=normal.normalized()
	if surface!=null and not local_normal.is_zero_approx(): facing=(surface.global_basis*local_normal).normalized()
	var up:=Vector3.RIGHT if absf(facing.dot(Vector3.UP))>0.95 else Vector3.UP
	var side:=up.cross(facing).normalized()
	var basis:=Basis(side,facing.cross(side).normalized(),facing).rotated(facing,randf()*TAU)
	var location:Vector3=surface.to_global(local_point) if surface!=null else point
	mark.global_transform=Transform3D(basis,location+facing*mark_surface_offset)
	var diameter:=glass_mark_size if impact_surface==&"glass" else metal_mark_size if impact_surface==&"metal" else snow_mark_size if impact_surface==&"snow" else concrete_mark_size
	mark.configure(textures.pick_random(),diameter*randf_range(0.85,1.15),mark_lifetime,mark_fade_seconds)

@rpc("authority", "call_local", "reliable", 2)
func _play_empty(effect_kind: StringName) -> void:
	_mechanism_audio.stream = rifle_empty_sound if effect_kind == &"m4a1" else pistol_empty_sound
	_mechanism_audio.play()
