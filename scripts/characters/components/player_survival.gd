class_name PlayerSurvival
extends Node

@export_group("Health")
@export_range(1.0, 1000.0) var max_health := 100.0
@export_group("Falls and respawn")
@export var safe_fall_speed: float = 11.0
@export var lethal_fall_speed: float = 22.0
@export var respawn_delay: float = 4.0
@export_group("Radiation")
@export_range(0.0, 100.0) var radiation_gain_per_second := 4.5
@export_range(0.0, 100.0) var radiation_recovery_per_second := 9.0
@export_range(0.0, 100.0) var radiation_damage_threshold := 35.0
@export_range(0.0, 5.0) var radiation_damage_scale := 0.22
var health: float = 100.0
var debug_invincible := false
var radiation: float = 0.0
var dead: bool = false
var reason: String = ""
var respawn_remaining: float = 0.0
var _fall_speed: float = 0.0
var _air_time: float = 0.0
var _spawn: Transform3D
var _hud: Label
var _cover: ColorRect
var _death_text: Label
var _sync_time: float = 0.0
var death_velocity := Vector3.ZERO
var pending_hit_impulse:=Vector3.ZERO
var death_hit_impulse:=Vector3.ZERO

func _ready() -> void:
	health = max_health
	_spawn = get_parent().global_transform
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	_cover = ColorRect.new()
	layer.add_child(_cover)
	_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cover.color = Color(0.08, 0.015, 0.01, 0.88)
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_text = Label.new()
	_cover.add_child(_death_text)
	_death_text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_death_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_death_text.add_theme_font_size_override("font_size", 30)
	_hud = Label.new()
	layer.add_child(_hud)
	_hud.position = Vector2(28, 110)
	_hud.add_theme_font_size_override("font_size", 22)
	_hud.add_theme_color_override("font_color", Color("ebc778"))
	_refresh_ui()

func reset_fall() -> void:
	_fall_speed = 0.0
	_air_time = 0.0

func observe_motion(incoming_y: float, grounded: bool, platform_y: float) -> void:
	if not multiplayer.is_server() or dead:
		return
	if grounded:
		var impact := maxf(_fall_speed, -incoming_y) + platform_y
		if impact > safe_fall_speed:
			damage(max_health * (impact - safe_fall_speed) / (lethal_fall_speed - safe_fall_speed), "Падение с высоты")
		reset_fall()
	else:
		_fall_speed = maxf(_fall_speed, -incoming_y)

func _physics_process(delta: float) -> void:
	var player := get_parent()
	if multiplayer.is_server():
		if dead:
			respawn_remaining = maxf(0.0, respawn_remaining - delta)
			if respawn_remaining <= 0.0:
				_respawn()
		elif not player.is_sleeping_in_bunk():
			var level := get_tree().get_first_node_in_group("expedition_level") as Node3D
			var local_pos: Vector3 = level.to_local(player.global_position) if level != null else player.global_position
			var bottom := -160.0 if level != null else -40.0
			# Horizontal limits are physical colliders in SnowExterior.
			# This fallback only catches a player that falls through the level.
			if local_pos.y < bottom:
				damage(max_health, "Выход за пределы комплекса")
			if not player.is_on_floor() and player.velocity.y < -2.0:
				_air_time += delta
				if _air_time > 3.0:
					damage(max_health, "Падение в шахту")
			else:
				_air_time = 0.0
			var exposure := 0.0
			for zone in get_tree().get_nodes_in_group("radiation_zones"):
				exposure += float(zone.intensity_at(player.global_position))
			radiation = clampf(radiation + (exposure * radiation_gain_per_second if exposure > 0.0 else -radiation_recovery_per_second) * delta, 0.0, 100.0)
			if radiation > radiation_damage_threshold:
				damage((radiation - radiation_damage_threshold) * radiation_damage_scale * delta, "Радиационное поражение")
		_sync_time += delta
		if _sync_time >= 0.15:
			_sync_time = 0.0
			_sync.rpc(health, radiation, dead, reason, respawn_remaining, death_velocity,death_hit_impulse)
	_refresh_ui()

func damage(amount: float, cause: String) -> void:
	if debug_invincible or get_parent().debug_fly:
		return
	if not multiplayer.is_server() or dead or amount <= 0.0:
		return
	health = maxf(0.0, health - amount)
	if amount >= 1.0:
		_blood.rpc()
	if health <= 0.0:
		dead = true
		reason = cause
		respawn_remaining = respawn_delay
		var player := get_parent()
		death_velocity = player.velocity
		death_hit_impulse=pending_hit_impulse
		player.velocity = Vector3.ZERO
		player._flashlight_enabled = false
		player._flashlight_malfunctioning = false
		if player._held_item_type == player.FLASHLIGHT_ITEM:
			player._held_item_type = player.NO_ITEM
		player._publish_inventory()
		_sync.rpc(health, radiation, dead, reason, respawn_remaining, death_velocity,death_hit_impulse)
	pending_hit_impulse=Vector3.ZERO

@rpc("authority", "call_local", "unreliable")
func _blood() -> void:
	var player := get_parent() as Node3D
	preload("res://scripts/gameplay/blood_effect.gd").spawn(player, player.global_position + Vector3.UP)

func _respawn() -> void:
	var player := get_parent()
	var target := _spawn
	var level := get_tree().get_first_node_in_group("expedition_level") as Node3D
	if level != null:
		var index := 0
		var world := get_tree().get_first_node_in_group("network_gameplay_controller")
		if world != null:
			index = world.get_peer_spawn_index(player.owner_peer_id)
		target = level.get_respawn_transform(index)
	player.teleport_authoritative(target.origin + Vector3.UP * 0.1, target.basis.get_euler().y)
	health = max_health
	radiation = 0.0
	dead = false
	death_hit_impulse=Vector3.ZERO
	reason = ""
	reset_fall()
	_sync.rpc(health, radiation, dead, reason, 0.0, Vector3.ZERO)

@rpc("authority", "call_local", "reliable", 2)
func _sync(hp: float, dose: float, is_dead: bool, cause: String, remaining: float, momentum: Vector3 = Vector3.ZERO, hit_impulse: Vector3 = Vector3.ZERO) -> void:
	var was_dead := dead
	health = hp
	radiation = dose
	dead = is_dead
	death_velocity = momentum
	death_hit_impulse=hit_impulse
	reason = cause
	respawn_remaining = remaining
	var player := get_parent()
	player.crosshair.visible = player.is_local_player() and not dead
	player.body_animator.set_sleeping(dead or player.is_sleeping_in_bunk())
	if dead:
		player._server_consumed_jump_serial = player._server_jump_serial
		player._server_consumed_flashlight_serial = player._server_flashlight_serial
		player._server_consumed_interact_serial = player._server_interact_serial
		player._server_consumed_drop_item_serial = player._server_drop_item_serial
	if dead and (not was_dead or get_parent().is_local_player()):
		var journal := get_node_or_null("/root/QuestJournal")
		if get_parent().is_local_player() and journal != null:
			journal.force_close()
	_refresh_ui()

func _refresh_ui() -> void:
	var local_player: bool = get_parent().is_local_player()
	_cover.visible = local_player and dead
	_death_text.text = "ВЫ ПОГИБЛИ\n%s\n\nВозвращение на базу: %d" % [reason, ceili(respawn_remaining)]
	_hud.visible = local_player and not dead and (health < 99.5 or radiation > 0.5)
	_hud.text = "Здоровье: %d%%" % ceili(health)
	if radiation > 0.5:
		_hud.text += "\n☢ Радиация: %d%% — покиньте зону" % ceili(radiation)
