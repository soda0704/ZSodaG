extends Control
## Presentation only: inventory, authority, damage, input and saves stay with their owners.
## Coordinates follow the supplied 2560×1440 manifest; wide screens keep edge anchors.

const WHITE := Color("efefe8")
const AMBER := Color("e2ad4d")
const TEAL := Color("84d8db")
const MUTED := Color("c3cbc9")
const LINE := Color(0.63, 0.72, 0.73, 0.26)
const FRAME_WIDTH := 1.0
const BODY_FONT := preload("res://assets/fonts/hud/body.tres")
const HEADING_FONT := preload("res://assets/fonts/hud/heading.tres")
const PISTOL_ICON := preload("res://assets/ui/northern_lab_hud/bonus/pistol_icon_4x.png")
const MARKER := preload("res://assets/ui/northern_lab_hud/bonus/teammate_world_marker_4x.png")
const CARD_SIZE := Vector2(178, 88)
const CARD_TOP_MARGIN := 184.0
const CARD_BODY_HEIGHT := 57.0
const PARALLAX := preload("res://scripts/ui/hud_parallax.gd")
const LAYOUT := preload("res://scripts/ui/hud_layout.gd")
const CAMERA_INK := LAYOUT.CAMERA_INK
const EDGE_INSET := 16.0
const ITEM_TITLES := {&"flamethrower":"Огнемёт",&"fuel_can": "Канистра",
	&"fuse": "Предохранитель", &"seed_packet": "Семена"}

var player: GamePlayer
var view_state: Dictionary = {}
var compass_heading := 0.0
var teammate: GamePlayer
var _font: Font = BODY_FONT
var _frame_style := StyleBoxFlat.new()
var _badge_metrics_cache: Dictionary = {}
var _elapsed := 0.0
var _recording_elapsed := 0.0
var _canvas_size := Vector2(2560, 1440)
var _layout_scale := 1.0
var _reveal := 0.0
var _prompt_alpha := 0.0
var _prompt_text := ""
var _prompt_progress := 0.0
var _prompt_absent_for := 0.0
var _draw_alpha := 1.0
var _health_ratio := 1.0
var _charge_ratio := 0.0
var _equipment_flash := 0.0
var _ammo_flash := 0.0
var _last_objective := ""
var _last_equipment := ""
var _last_rounds := -1
var _animated_state_initialized := false
var _objective_view: Dictionary = {}
var _objective_pending: Dictionary = {}
var _objective_phase := 0
var _objective_time := 0.0
var _objective_alpha := 1.0
var _objective_from_alpha := 1.0
var _task_motion: Dictionary = {}
var _departing_tasks: Array[Dictionary] = []
var _task_time := 0.0
var _equipment_view: Dictionary = {}
var _equipment_pending: Dictionary = {}
var _equipment_phase := 0
var _equipment_alpha := 1.0
var _equipment_from_alpha := 1.0
var _equipment_time := 0.0
var _teammate_reveal := 0.0
var _teammate_health := 1.0
var _teammate_id := 0
var _parallax := PARALLAX.new()
var _parallax_camera_id := 0
var _parallax_position := Vector3.ZERO
var _radiation_blades: Array[PackedVector2Array] = []
@onready var _camera_effect = get_node("../CameraPostProcess")

static func motion_curve(value: float) -> float:
	# Smoothstep: zero velocity at both ends, no overshoot, independent of frame rate.
	var t := clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func _ready() -> void:
	player = get_parent().get_parent() as GamePlayer
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	hide()
	add_to_group("hud_layout")
	get_viewport().size_changed.connect(_layout)
	for blade in 3:
		var points := PackedVector2Array()
		var direction := -PI * 0.5 + blade * TAU / 3.0
		for index in 9:
			points.append(Vector2.from_angle(direction + lerpf(-0.47, 0.47, index / 8.0)) * 16.0)
		for index in range(8, -1, -1):
			points.append(Vector2.from_angle(direction + lerpf(-0.47, 0.47, index / 8.0)) * 6.5)
		_radiation_blades.append(points)
	_layout()

func _layout() -> void:
	var viewport_size := get_viewport_rect().size
	_layout_scale = LAYOUT.scale_for(get_viewport())
	var quality := get_node("/root/GameMenu/GraphicsQuality")
	var safe := LAYOUT.safe_rect(viewport_size, float(quality.values.get("HUDMargin", 0)))
	position = safe.position
	_canvas_size = safe.size / _layout_scale
	scale = Vector2.ONE * _layout_scale
	size = _canvas_size
	queue_redraw()

func _process(delta: float) -> void:
	if not is_instance_valid(player) or player.survival == null or player.weapon == null:
		return
	visible = should_display()
	if not visible:
		_parallax.reset()
		_parallax_camera_id = 0
		_reveal = 0.0
		_prompt_alpha = 0.0
		_prompt_progress = 0.0
		_prompt_absent_for = 0.0
		_prompt_text = ""
		_animated_state_initialized = false
		_elapsed = 0.1
		return
	_recording_elapsed += delta
	_elapsed += delta
	if view_state.is_empty() or _elapsed >= 0.1:
		_elapsed = 0.0
		refresh_state()
	var forward := -player.camera.global_basis.z
	compass_heading = fposmod(rad_to_deg(atan2(forward.x, -forward.z)), 360.0)
	_update_parallax(forward, delta)
	var notice: Control = $PowerSwitchNotice
	if notice.visible:
		var notice_plane := panel_transform(Vector2(-1, 1))
		notice.position = notice_plane * Vector2(_canvas_size.x - 352.0, 42.0)
		notice.rotation = notice_plane.get_rotation()
		notice.scale = notice_plane.get_scale()
	_update_animations(delta)
	queue_redraw()

func _update_parallax(forward: Vector3, delta: float) -> void:
	var camera_id := player.camera.get_instance_id()
	if camera_id != _parallax_camera_id or player.global_position.distance_squared_to(_parallax_position) > 9.0:
		_parallax.reset()
	_parallax_camera_id = camera_id
	_parallax_position = player.global_position
	var camera_yaw := atan2(-forward.x, -forward.z)
	var local_velocity := Basis(Vector3.UP, camera_yaw).transposed() * player.velocity
	_parallax.sample(forward, delta, local_velocity, player.camera.get_hud_displacement(), player.camera.get_hud_roll())

func panel_transform(edge: Vector2) -> Transform2D:
	match edge:
		Vector2(1, 1):
			return floating_panel_transform(Vector2(72, 182), edge, 1.12)
		Vector2(-1, 1):
			return floating_panel_transform(Vector2(_canvas_size.x - 190, 86), edge, 0.84)
		Vector2(1, -1):
			var anchor := Vector2(88, _canvas_size.y - LAYOUT.PRIMARY_STATUS_INSET)
			var zoom := LAYOUT.HEALTH_SCALE
			var health_scale := Transform2D(0.0, Vector2.ONE * zoom, 0.0, anchor * (1.0 - zoom))
			return floating_panel_transform(anchor, edge, 0.9) * health_scale
		Vector2(-1, -1):
			return floating_panel_transform(_canvas_size - Vector2(166, LAYOUT.PRIMARY_STATUS_INSET), edge, 0.9)
		Vector2(0, 1):
			return floating_panel_transform(Vector2(_canvas_size.x * 0.5, 64), edge, 0.63, Vector2.ZERO)
		Vector2(0, -1):
			return floating_panel_transform(Vector2(_canvas_size.x * 0.5, _canvas_size.y - 115), edge, 0.67)
		_:
			return floating_panel_transform(_canvas_size * 0.5, Vector2.ZERO, 0.34)

func floating_panel_transform(anchor: Vector2, edge: Vector2, depth: float, base_inset: Vector2 = Vector2.ONE * EDGE_INSET) -> Transform2D:
	# Project the two axes of a plane facing inward toward the camera. Each group
	# uses its own pivot and depth, so it can drift without pulling the reticle.
	var motion: Vector3 = _parallax.movement
	var lag := (Vector2(_parallax.offset.x, _parallax.pitch_offset) + Vector2(motion.x, motion.y)).limit_length(22.0)
	var corner_slant := edge.x * (0.043 if edge.y >= 0.0 else -0.024)
	var slant := (corner_slant + lag.x * 0.0011) * depth
	var tilt := (edge.x * 0.022 + lag.y * 0.0011) * depth
	var pitch_scale := (absf(edge.y) * 0.023 + absf(lag.y) * 0.0013) * depth
	var perspective := 1.0 / (1.0 + motion.z * depth)
	var roll := _parallax.roll * depth
	var axes := Transform2D(Vector2(1.0 - absf(slant) * 0.42, slant).rotated(roll) * perspective,
		Vector2(-tilt, 1.0 - pitch_scale).rotated(roll) * perspective, Vector2.ZERO)
	var depth_shift := ((anchor - _canvas_size * 0.5) * (perspective - 1.0)).limit_length(24.0)
	var inset := base_inset + LAYOUT.content_inset(_canvas_size)
	axes.origin = anchor - axes * anchor + edge * inset + lag * depth + depth_shift
	return axes

func get_parallax_offset_pixels() -> Vector2:
	return _parallax.offset * _layout_scale if visible else Vector2.ZERO

func _update_animations(delta: float) -> void:
	_reveal = move_toward(_reveal, 1.0, delta / 0.20)
	modulate.a = motion_curve(_reveal)
	var incoming := current_prompt()
	if not incoming.is_empty() and incoming != _prompt_text:
		# Live counters may change every frame; keep them readable instead of restarting a fade.
		if _prompt_text.is_empty() or _prompt_alpha <= 0.0:
			_prompt_progress = 0.0
		_prompt_text = incoming
	_prompt_absent_for = _prompt_absent_for + delta if incoming.is_empty() else 0.0
	# A 50 ms grace period absorbs a one-frame raycast miss at an object's edge.
	var prompt_target := 0.0 if _prompt_absent_for >= 0.05 else 1.0
	if _prompt_text.is_empty(): prompt_target = 0.0
	_prompt_progress = move_toward(_prompt_progress, prompt_target, delta / (0.10 if prompt_target == 0 else 0.16))
	_prompt_alpha = motion_curve(_prompt_progress)
	if _prompt_alpha <= 0.0:
		_prompt_text = ""
	if view_state.is_empty():
		return
	var hp := clampf(float(view_state.health) / float(view_state.max_health), 0, 1)
	var charge := clampf(float(view_state.battery_charge), 0, 1)
	if not _animated_state_initialized:
		_health_ratio = hp
		_charge_ratio = charge
		_objective_view = objective_layout(view_state.quest)
		_objective_pending = _objective_view
		_objective_alpha = 1.0
		_objective_phase = 0
		_task_motion.clear()
		_departing_tasks.clear()
		_equipment_view = equipment_layout(view_state)
		_equipment_pending = _equipment_view
		_equipment_alpha = 1.0
		_equipment_phase = 0
		_animated_state_initialized = true
	else:
		_health_ratio = lerpf(_health_ratio, hp, 1.0 - exp(-10.0 * delta))
		_charge_ratio = lerpf(_charge_ratio, charge, 1.0 - exp(-10.0 * delta))
		if absf(_health_ratio - hp) < 0.0005: _health_ratio = hp
		if absf(_charge_ratio - charge) < 0.0005: _charge_ratio = charge
	_update_objective_motion(delta)
	_update_equipment_motion(delta)
	if is_instance_valid(teammate):
		_teammate_reveal = move_toward(_teammate_reveal, 1.0, delta / 0.20)
		var teammate_hp := clampf(teammate.survival.health / teammate.survival.max_health, 0, 1)
		_teammate_health = lerpf(_teammate_health, teammate_hp, 1.0 - exp(-10.0 * delta))
	_equipment_flash = maxf(0.0, _equipment_flash - delta * 2.8)
	_ammo_flash = maxf(0.0, _ammo_flash - delta * 5.0)

func _update_objective_motion(delta: float) -> void:
	_task_time += delta
	if _task_time >= 0.44:
		_task_motion.clear()
	for index in range(_departing_tasks.size() - 1, -1, -1):
		_departing_tasks[index].age += delta
		if _departing_tasks[index].age >= 0.36:
			_departing_tasks.remove_at(index)
	_objective_time += delta
	match _objective_phase:
		1:
			_objective_alpha = _objective_from_alpha * (1.0 - motion_curve(_objective_time / 0.08))
			if _objective_time >= 0.08:
				_objective_view = _objective_pending
				_objective_phase = 2
				_objective_time = 0.0
		2:
			_objective_alpha = motion_curve(_objective_time / 0.14)
			if _objective_time >= 0.14: _objective_phase = 0

func _task_pose(row: Dictionary) -> Vector3:
	var motion: Dictionary = _task_motion.get(row.source, {})
	if motion.is_empty():
		return Vector3(0.0, row.y, 1.0)
	var t := motion_curve((_task_time - float(motion.delay)) / 0.19)
	return Vector3(lerpf(float(motion.x), 0.0, t), lerpf(float(motion.y), row.y, t), lerpf(float(motion.alpha), 1.0, t))

func _transition_task_list(next: Dictionary, completed: Array) -> void:
	var old_poses := {}
	var next_sources := {}
	for row in next.rows:
		next_sources[row.source] = true
	var delay := 0.0
	for index in range(_departing_tasks.size() - 1, -1, -1):
		var departing: Dictionary = _departing_tasks[index]
		if next_sources.has(departing.row.source):
			old_poses[departing.row.source] = _departing_task_pose(departing)
			_departing_tasks.remove_at(index)
		else:
			delay = maxf(delay, 0.25 - float(departing.age))
	for row in _objective_view.rows:
		var pose := _task_pose(row)
		old_poses[row.source] = pose
		if not next_sources.has(row.source) and pose.z > 0.01:
			_departing_tasks.append({"row": row, "pose": pose, "completed": completed.has(row.source), "age": 0.0})
			delay = 0.25
	_task_motion.clear()
	_task_time = 0.0
	for row in next.rows:
		var previous: Vector3 = old_poses.get(row.source, Vector3(-10.0, row.y + 4.0, 0.0))
		_task_motion[row.source] = {"x": previous.x, "y": previous.y, "alpha": previous.z, "delay": delay}
	_objective_view = next

func _departing_task_pose(task: Dictionary) -> Vector3:
	var pose: Vector3 = task.pose
	var leave := motion_curve((float(task.age) - 0.12) / 0.24)
	return Vector3(pose.x + 8.0 * leave, pose.y, pose.z * (1.0 - leave))

func _update_equipment_motion(delta: float) -> void:
	_equipment_time += delta
	match _equipment_phase:
		1:
			_equipment_alpha = _equipment_from_alpha * (1.0 - motion_curve(_equipment_time / 0.08))
			if _equipment_time >= 0.08:
				_equipment_view = _equipment_pending
				_equipment_phase = 2
				_equipment_time = 0.0
		2:
			_equipment_alpha = motion_curve(_equipment_time / 0.16)
			if _equipment_time >= 0.16: _equipment_phase = 0

func should_display() -> bool:
	return player.is_gameplay_view_active()

func current_prompt() -> String:
	if player.needs_flashlight_shake() and not player.is_climbing() and not player.is_driving() and not player.handoff.is_offering():
		return "%s Встряхнуть фонарь" % get_node("/root/SteamInput").get_action_hint(&"interact")
	return player.interaction_prompt.strip_edges()

func refresh_state() -> void:
	var journal := get_node("/root/QuestJournal")
	view_state = player.get_inventory_snapshot()
	if player.handoff.pocket_pose() or player.get_node("ItemDrag").is_heavy_carrying(): view_state["held_item"] = &""
	if player.get_node("ItemDrag").is_heavy_carrying(): view_state["has_flashlight"] = false
	view_state["health"] = player.survival.health
	view_state["max_health"] = player.survival.max_health
	# The game models radiation as a 0–100 exposure gauge, not a measured dose.
	view_state["radiation"] = player.survival.radiation
	view_state["quest"] = journal.get_hud_summary()
	view_state["light_hint"] = _action_hint(&"flashlight")
	view_state["attack_hint"] = "" if player.handoff.is_offering() or player.get_node("ItemDrag").is_heavy_carrying() else _action_hint(&"weapon_attack")
	view_state["journal_hint"] = get_node("/root/SteamInput").get_action_hint(&"journal")
	view_state["journal_unread"] = journal.has_unread_entries()
	view_state["has_journal"] = player.has_journal
	view_state["reload_hint"] = get_node("/root/SteamInput").get_action_hint(&"replace_battery")
	view_state["reload_action"] = &"" if player.handoff.is_offering() or player.get_node("ItemDrag").is_heavy_carrying() else player.get_reload_or_battery_action()
	view_state["battery_action_busy"] = player._battery_action_busy
	var world := get_tree().get_first_node_in_group("network_gameplay_controller")
	view_state["arrival"] = world != null and world.has_method("is_waiting_for_arrival") and world.is_waiting_for_arrival()
	var objective := str(view_state.quest)
	if not _last_objective.is_empty() and objective != _last_objective:
		_objective_pending = objective_layout(view_state.quest)
		if _animated_state_initialized and _objective_phase == 0 and _objective_view.context == _objective_pending.context:
			_transition_task_list(_objective_pending, view_state.quest.get("completed", []))
		elif _animated_state_initialized and _objective_phase != 1:
			_task_motion.clear()
			_departing_tasks.clear()
			_objective_phase = 1
			_objective_time = 0.0
			_objective_from_alpha = _objective_alpha
	_last_objective = objective
	var equipment := str(view_state.held_item)
	if _animated_state_initialized and equipment != _last_equipment:
		_equipment_flash = 1.0
		_equipment_pending = equipment_layout(view_state)
		if _animated_state_initialized and _equipment_phase != 1:
			_equipment_phase = 1
			_equipment_time = 0.0
			_equipment_from_alpha = _equipment_alpha
	elif _equipment_phase == 0:
		# Rebinding updates the action prompt without replaying the reveal.
		_equipment_view = equipment_layout(view_state)
	else:
		_equipment_pending = equipment_layout(view_state)
	_last_equipment = equipment
	var rounds := int(view_state.weapon_rounds)
	if _last_rounds >= 0 and rounds > _last_rounds:
		_ammo_flash = 1.0
	_last_rounds = rounds
	teammate = null
	for actor in get_tree().get_nodes_in_group("network_players"):
		if actor is GamePlayer and actor != player and not actor.is_local_player():
			teammate = actor
			break
	var teammate_id := teammate.get_instance_id() if is_instance_valid(teammate) else 0
	if teammate_id != _teammate_id:
		_teammate_id = teammate_id
		_teammate_reveal = 0.0
		_teammate_health = teammate.survival.health / teammate.survival.max_health if is_instance_valid(teammate) else 1.0
	queue_redraw()

func _action_hint(action: StringName) -> String:
	var service := get_node("/root/SteamInput")
	if service.using_controller:
		if action == &"weapon_attack":
			return "R2" if service.controller_family == "playstation" else "RT"
	else:
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				return OS.get_keycode_string(event.physical_keycode if event.physical_keycode != 0 else event.keycode)
			if event is InputEventMouseButton:
				return {MOUSE_BUTTON_LEFT: "ЛКМ", MOUSE_BUTTON_RIGHT: "ПКМ", MOUSE_BUTTON_MIDDLE: "СКМ"}.get(event.button_index, "Мышь %d" % event.button_index)
	return str(service.get_action_hint(action)).trim_prefix("[").trim_suffix("]").strip_edges()

func _draw() -> void:
	if view_state.is_empty() or not is_instance_valid(player):
		return
	LAYOUT.draw_camera_corners(self, _canvas_size)
	if should_draw_reticle():
		LAYOUT.draw_reticle(self, _canvas_size * 0.5)
	draw_set_transform_matrix(panel_transform(Vector2(0, 1)))
	_draw_compass()
	draw_set_transform_matrix(panel_transform(Vector2(1, 1)))
	_draw_recording()
	_draw_objectives()
	draw_set_transform_matrix(panel_transform(Vector2(-1, 1)))
	_draw_teammate()
	draw_set_transform_matrix(panel_transform(Vector2.ZERO))
	_draw_interaction()
	var health_transform := panel_transform(Vector2(1, -1))
	draw_set_transform_matrix(health_transform)
	_draw_health(health_transform)
	draw_set_transform_matrix(panel_transform(Vector2(0, -1)))
	_draw_equipment()
	draw_set_transform_matrix(panel_transform(Vector2(-1, -1)))
	_draw_ammunition_and_light()
	draw_set_transform(Vector2.ZERO)

func recording_timecode() -> String:
	var seconds := floori(_recording_elapsed)
	return "%02d:%02d:%02d" % [floori(seconds / 3600.0), floori(seconds / 60.0) % 60, seconds % 60]

func _draw_recording() -> void:
	# Keep the camera clock at its calibrated rest position while it shares the task plane.
	var inset := Vector2.ONE * EDGE_INSET
	var pulse := 0.70 + 0.30 * cos(_recording_elapsed * TAU / 1.8)
	draw_circle(LAYOUT.RECORD_DOT - inset, 11.0, Color(LAYOUT.RECORD_RED, 0.10 * pulse), true, -1.0, true)
	draw_circle(LAYOUT.RECORD_DOT - inset, 7.0, Color(LAYOUT.RECORD_RED, pulse), true, -1.0, true)
	_text("ЗАПИСЬ", LAYOUT.RECORD_LABEL - inset, 30, CAMERA_INK)
	_text(recording_timecode(), LAYOUT.RECORD_CLOCK - inset, 27, CAMERA_INK)

func should_draw_reticle() -> bool:
	return not player._aiming

func _text(value: String, at: Vector2, font_size: int = 24, color: Color = WHITE, width: float = -1.0, heading: bool = false) -> void:
	var font: Font = HEADING_FONT if heading else _font
	# A tight vertical shadow supports the high-resolution glyphs on bright scenery.
	draw_string(font, at + Vector2(1, 2), value, HORIZONTAL_ALIGNMENT_LEFT, width, font_size, Color(0, 0, 0, 0.84 * _draw_alpha))
	var glow := color.lerp(LAYOUT.CAMERA_GLOW, 0.35)
	draw_string_outline(font, at, value, HORIZONTAL_ALIGNMENT_LEFT, width, font_size, 4, Color(glow, color.a * _draw_alpha * 0.085))
	draw_string(font, at, value, HORIZONTAL_ALIGNMENT_LEFT, width, font_size, _ink(color))

func _ink(color: Color) -> Color:
	return Color(color, color.a * _draw_alpha)

func _panel(rect: Rect2, fill: Color, border: Color, radius: int = 5) -> void:
	# One rounded shape keeps the translucent fill and thin border on the same contour.
	_frame_style.bg_color = _ink(fill)
	_frame_style.border_color = _ink(border)
	_frame_style.draw_center = fill.a > 0.0
	_frame_style.set_border_width_all(int(FRAME_WIDTH))
	_frame_style.set_corner_radius_all(mini(radius, floori(minf(rect.size.x, rect.size.y) * 0.5)))
	_frame_style.corner_detail = 8
	_frame_style.anti_aliasing = true
	draw_style_box(_frame_style, rect)

func _outline(rect: Rect2, color: Color) -> void:
	_panel(rect, Color.TRANSPARENT, color, 3)

func _wrapped(value: String, at: Vector2, font_size: int, width: float, color: Color, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> float:
	draw_multiline_string(_font, at + Vector2(0, 1), value, alignment, width, font_size, -1, Color(0, 0, 0, 0.85 * _draw_alpha))
	draw_multiline_string(_font, at, value, alignment, width, font_size, -1, _ink(color))
	return _font.get_multiline_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, width, font_size).y

func _badge_extent(value: String, font_size: int = 22) -> Vector2:
	return _badge_metrics(value, font_size).extent

func _badge_metrics(value: String, font_size: int) -> Dictionary:
	var cache_key := "%d/%s" % [font_size, value]
	if _badge_metrics_cache.has(cache_key): return _badge_metrics_cache[cache_key]
	var line := TextLine.new()
	line.add_string(value, _font, font_size)
	var server := TextServerManager.get_primary_interface()
	var bounds := Rect2()
	var has_ink := false
	var advance := 0.0
	# Center the visible glyphs, including font bearings and controller fallback fonts.
	for glyph in server.shaped_text_get_glyphs(line.get_rid()):
		for repeat_index in int(glyph.repeat):
			if glyph.font_rid.is_valid():
				var glyph_size := server.font_get_glyph_size(glyph.font_rid, Vector2i(glyph.font_size, 0), glyph.index)
				var glyph_offset := server.font_get_glyph_offset(glyph.font_rid, Vector2i(glyph.font_size, 0), glyph.index)
				if glyph_size.x > 0.0 and glyph_size.y > 0.0:
					var ink := Rect2(Vector2(advance, 0) + glyph.offset + glyph_offset, glyph_size)
					bounds = bounds.merge(ink) if has_ink else ink
					has_ink = true
			advance += float(glyph.advance)
	if not has_ink:
		bounds = Rect2(Vector2(0, -line.get_line_ascent()), line.get_size())
	var extent := Vector2(maxf(24, maxf(line.get_size().x, bounds.size.x) + 12), maxf(font_size + 10, bounds.size.y + 10))
	var result := {"extent": extent, "baseline": extent * 0.5 - bounds.get_center()}
	_badge_metrics_cache[cache_key] = result
	return result

func _badge(value: String, at: Vector2, font_size: int = 22) -> float:
	var extent := _badge_extent(value, font_size)
	_panel(Rect2(at, extent), Color(0.025, 0.04, 0.045, 0.25), Color(WHITE, 0.32), 3)
	_text(value, at + _badge_metrics(value, font_size).baseline, font_size)
	return extent.x

func _fit_lines(value: String, width: float, font_size: int, max_lines: int) -> String:
	# Shaped multiline text rounds each line up to a whole pixel.
	var line_height := ceilf(_font.get_height(font_size))
	if _font.get_multiline_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, width, font_size).y <= line_height * max_lines + 1:
		return value
	var shortened := value
	while not shortened.is_empty() and _font.get_multiline_string_size(shortened + "…", HORIZONTAL_ALIGNMENT_LEFT, width, font_size).y > line_height * max_lines + 1:
		shortened = shortened.left(-1).strip_edges()
	return shortened.trim_suffix(",").trim_suffix(".") + "…"

func objective_layout(quest: Dictionary) -> Dictionary:
	var tasks: Array = quest.get("tasks", []).filter(func(task): return not str(task).strip_edges().is_empty())
	var result := {"rect": Rect2(44, 182, 440, 58), "empty": tasks.is_empty() and not bool(quest.get("title_only", false)),
		"empty_label": str(quest.get("empty_label", "НЕТ АКТИВНЫХ ЗАДАЧ")), "rows": [], "footer": "", "title": "",
		"context": [quest.get("day", 0), quest.get("objective", "")]}
	if result.empty:
		result.rect.size.x = maxf(240, HEADING_FONT.get_string_size(result.empty_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 62)
		return result
	var title := str(quest.get("objective", "Текущая задача")).strip_edges()
	if title.is_empty(): title = "Текущая задача"
	result.title = _fit_lines(title, 388, 28, 2)
	result.title_y = 18 + HEADING_FONT.get_height(18) + 10
	var y: float = result.title_y + _font.get_multiline_string_size(result.title, HORIZONTAL_ALIGNMENT_LEFT, 388, 28).y + 16
	var abbreviated: bool = result.title != title
	for task in tasks.slice(0, 2):
		var content := _fit_lines(str(task), 370, 24, 3)
		result.rows.append({"text": content, "source": str(task), "y": y})
		abbreviated = abbreviated or content != str(task)
		y += _font.get_multiline_string_size(content, HORIZONTAL_ALIGNMENT_LEFT, 370, 24).y + 10
	if tasks.size() > 2 or abbreviated:
		result.footer = "ЕЩЁ %d" % (tasks.size() - 2) if tasks.size() > 2 else "ПОДРОБНЕЕ"
		result.footer_y = y + 4
		y += _font.get_height(18) + 4
	result.rect.size.y = y + 10
	return result

func _draw_objectives() -> void:
	# The initial unknown objective also belongs beside the helicopter lobby card.
	var quest: Dictionary = view_state.quest
	var day := int(quest.get("day", 0))
	if day <= 0 or _objective_view.is_empty(): return
	var heading := "ДЕНЬ %02d" % day
	if player.global_position.y < -12.0:
		heading += "  /  ПОДЗЕМНЫЙ КОМПЛЕКС"
	_text(heading, Vector2(48, 170), 21, MUTED, -1, true)
	var layout := _objective_view
	var panel: Rect2 = layout.rect
	_draw_alpha = _objective_alpha
	if layout.empty:
		_draw_alpha *= motion_curve((_task_time - 0.25) / 0.11) if not _departing_tasks.is_empty() else 1.0
		draw_circle(panel.position + Vector2(24, 29), 3, _ink(TEAL))
		_text(layout.empty_label, panel.position + Vector2(38, 29 + HEADING_FONT.get_ascent(18) - HEADING_FONT.get_height(18) * 0.5), 18, MUTED, -1, true)
	else:
		_text("ТЕКУЩАЯ ЗАДАЧА", panel.position + Vector2(26, 18 + HEADING_FONT.get_ascent(18)), 18, MUTED, -1, true)
		draw_rect(Rect2(panel.position + Vector2(0, layout.title_y + 4), Vector2(1, 24)), _ink(AMBER))
		_wrapped(layout.title, panel.position + Vector2(26, layout.title_y + _font.get_ascent(28)), 28, 388, AMBER)
		for row in layout.rows:
			var pose := _task_pose(row)
			_draw_alpha = _objective_alpha * pose.z
			_draw_task_row(row.text, panel.position + Vector2(pose.x, pose.y))
		_draw_alpha = _objective_alpha
		if not str(layout.footer).is_empty():
			_text(layout.footer, panel.position + Vector2(26, layout.footer_y + _font.get_ascent(18)), 18, MUTED)
	for task in _departing_tasks:
		var pose := _departing_task_pose(task)
		_draw_alpha = _objective_alpha * pose.z
		_draw_task_row(task.row.text, panel.position + Vector2(pose.x, pose.y), float(task.age) if task.completed else -1.0)
	_draw_alpha = 1.0

func _draw_task_row(text: String, origin: Vector2, completion_age: float = -1.0) -> void:
	var baseline := _font.get_ascent(24)
	var bullet := origin + Vector2(29, baseline - 7)
	var completed := completion_age >= 0.0
	if completed:
		var stroke := motion_curve(completion_age / 0.13)
		var start := bullet + Vector2(-5, 0)
		var joint := bullet + Vector2(-1, 4)
		draw_line(start, start.lerp(joint, minf(stroke * 2.0, 1.0)), _ink(TEAL), 2, true)
		if stroke > 0.5:
			draw_line(joint, joint.lerp(bullet + Vector2(6, -4), (stroke - 0.5) * 2.0), _ink(TEAL), 2, true)
	else:
		draw_circle(bullet, 2, _ink(MUTED))
	_wrapped(text, origin + Vector2(46, baseline), 24, 370, TEAL if completed else WHITE)

func compass_layout() -> Rect2:
	# Preserve room for the day/objective header on narrow and 4:3 screens.
	var width := minf(560, maxf(280, _canvas_size.x - 1080))
	return Rect2((_canvas_size.x - width) * 0.5, 38, width, 64)

func _draw_compass() -> void:
	var center := _canvas_size.x * 0.5
	var rect := compass_layout()
	var left := rect.position.x
	draw_line(Vector2(left, 65), Vector2(rect.end.x, 65), Color(0, 0, 0, 0.60), 2.0, true)
	draw_line(Vector2(left, 64), Vector2(rect.end.x, 64), Color(LAYOUT.CAMERA_GLOW, 0.09), 5.0, true)
	draw_line(Vector2(left, 64), Vector2(rect.end.x, 64), Color(CAMERA_INK, 0.64), 1.5, true)
	var labels := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	for tick in range(-32, 65):
		var degrees := tick * 11.25
		var x := center + (degrees - compass_heading) * 3.0
		if x < left + 24 or x > rect.end.x - 24:
			continue
		var major := posmod(tick, 4) == 0
		draw_line(Vector2(x, 52 if major else 57), Vector2(x, 64), Color(CAMERA_INK, 0.60), 1.5, true)
		if major:
			var label: String = labels[posmod(floori(tick / 4.0), 8)]
			var text_width := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
			_text(label, Vector2(x - text_width * 0.5, 47), 26, CAMERA_INK)
	draw_colored_polygon(PackedVector2Array([Vector2(center - 7, 79), Vector2(center + 7, 79), Vector2(center, 71)]), CAMERA_INK)

func _draw_teammate() -> void:
	if not is_instance_valid(teammate) or teammate.survival == null:
		return
	_draw_alpha = motion_curve(_teammate_reveal)
	var x := _canvas_size.x - 270
	# The helicopter's right-hand lobby card owns the first row during arrival.
	var row := 188.0 if bool(view_state.get("arrival", false)) else 0.0
	_text("НАПАРНИК", Vector2(x + 6, row + 57), 20, MUTED, -1, true)
	var distance := player.global_position.distance_to(teammate.global_position)
	_text("%d м" % roundi(distance), Vector2(x + 6, row + 96), 23)
	_outline(Rect2(x + 99, row + 84, 125, 10), Color(TEAL, 0.34))
	draw_rect(Rect2(x + 102, row + 87, 119 * _teammate_health, 4), _ink(WHITE))
	if teammate.survival.dead:
		_text("Возрождение…", Vector2(x + 6, row + 123), 20, AMBER)
		_draw_alpha = 1.0
		return
	var world_point := teammate.global_position + Vector3(0, 2.3, 0)
	# World anchors stay registered to the target, independently of panel inertia.
	draw_set_transform(Vector2.ZERO)
	var camera_point := player.camera.get_camera_transform().affine_inverse() * world_point
	if camera_point.z < -player.camera.near:
		var screen_point := player.camera.unproject_position(world_point)
		screen_point = _camera_effect.project_overlay_point(screen_point)
		if get_viewport_rect().grow(-30).has_point(screen_point):
			draw_texture_rect(MARKER, Rect2((screen_point - position) / _layout_scale - Vector2(16, 16), Vector2(32, 32)), false, _ink(WHITE))
	_draw_alpha = 1.0

func interaction_layout(source: String) -> Dictionary:
	var prompt := source.strip_edges()
	var key := ""
	# Only explicit actionable hints get a keycap. Informational/blocked hints stay informational.
	if prompt.begins_with("[") and prompt.contains("]"):
		var end := prompt.find("]")
		key = prompt.substr(1, end - 1).strip_edges()
		prompt = prompt.substr(end + 1).strip_edges()
	var key_size := _badge_extent(key, 22) if not key.is_empty() else Vector2.ZERO
	# Symmetric reserves keep the text centered on the entire frame, independently of the key.
	var indent := key_size.x + 24 if not key.is_empty() else 16.0
	# Small counter changes stay in the same width bucket instead of vibrating the card.
	var width := clampf(ceilf((_font.get_string_size(prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x + indent * 2) / 24.0) * 24.0, 240, 660)
	# Bound exceptional long messages before the bottom HUD, while preserving the action key.
	prompt = _fit_lines(prompt, width - indent * 2, 24, 6)
	var height := maxf(maxf(44, key_size.y + 12), _font.get_multiline_string_size(prompt, HORIZONTAL_ALIGNMENT_LEFT, width - indent * 2, 24).y + 14)
	var at := Vector2((_canvas_size.x - width) * 0.5, _canvas_size.y * 0.5 + 44)
	if height <= 52.0 and not key.is_empty():
		at = Vector2(_canvas_size.x * 0.5 + 62.0, (_canvas_size.y - height) * 0.5)
	return {"rect": Rect2(at, Vector2(width, height)), "text": prompt, "key": key, "key_size": key_size, "indent": indent, "text_width": width - indent * 2}

func _draw_interaction() -> void:
	if _prompt_text.is_empty() or _prompt_alpha <= 0.0:
		return
	var layout := interaction_layout(_prompt_text)
	var rect: Rect2 = layout.rect
	_draw_alpha = _prompt_alpha
	var key := str(layout.key)
	if not key.is_empty():
		_text("[%s]" % key, rect.position + Vector2(10, rect.size.y * 0.5 + 8), 22, CAMERA_INK)
	var text_height := _font.get_multiline_string_size(str(layout.text), HORIZONTAL_ALIGNMENT_LEFT, layout.text_width, 24).y
	_wrapped(str(layout.text), rect.position + Vector2(float(layout.indent), (rect.size.y - text_height) * 0.5 + _font.get_ascent(24)), 24, layout.text_width, WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_draw_alpha = 1.0

func _draw_health(panel: Transform2D) -> void:
	var top := _canvas_size.y - LAYOUT.PRIMARY_STATUS_INSET
	var hp := float(view_state.health)
	var color := AMBER if _health_ratio < 0.3 else CAMERA_INK
	draw_line(Vector2(78, top - 11), Vector2(98, top - 11), color, 4.0, true)
	draw_line(Vector2(88, top - 21), Vector2(88, top - 1), color, 4.0, true)
	var value := str(ceili(hp))
	_text(value, Vector2(110, top), 34, color)
	var bar_x := 128 + _font.get_string_size(str(ceili(view_state.max_health)), HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
	draw_line(Vector2(bar_x, top - 10), Vector2(bar_x + 144, top - 10), Color(0, 0, 0, 0.48), 5.0, true)
	if _health_ratio > 0.0:
		draw_line(Vector2(bar_x, top - 10), Vector2(bar_x + 144 * _health_ratio, top - 10), Color(color, 0.12), 8.0, true)
		draw_line(Vector2(bar_x, top - 10), Vector2(bar_x + 144 * _health_ratio, top - 10), color, 3.0, true)
	var radiation := float(view_state.radiation)
	var warning := radiation >= player.survival.radiation_damage_threshold
	var radiation_ink := AMBER if warning else CAMERA_INK
	draw_set_transform_matrix(panel * Transform2D(0.0, Vector2.ONE * 0.78, 0.0, Vector2(88, top + 27)))
	for blade in _radiation_blades:
		draw_colored_polygon(blade, radiation_ink)
	draw_circle(Vector2.ZERO, 4, radiation_ink, true, -1.0, true)
	draw_set_transform_matrix(panel)
	_text("%.0f%%" % radiation, Vector2(110, top + 36), 27, radiation_ink)
	if warning:
		_text("Покиньте зону", Vector2(110, top + 62), 20, AMBER)

func equipment_layout(snapshot: Dictionary) -> Dictionary:
	var hand := StringName(snapshot.get("held_item", &""))
	if hand in [&"", &"flashlight"]:
		return {}
	var hint := str(snapshot.get("attack_hint", "ЛКМ")) if WeaponController.TYPES.has(hand) or hand == &"flamethrower" else ""
	var at := Vector2((_canvas_size.x - CARD_SIZE.x) * 0.5, _canvas_size.y - CARD_TOP_MARGIN)
	return {"item": hand, "hint": hint, "rect": Rect2(at, CARD_SIZE)}

func _draw_equipment() -> void:
	_draw_alpha = _equipment_alpha
	if not _equipment_view.is_empty():
		var hand := StringName(_equipment_view.item)
		var at := Vector2((_canvas_size.x - CARD_SIZE.x) * 0.5, _canvas_size.y - CARD_TOP_MARGIN)
		var hint := str(_equipment_view.hint).replace(" / Create", "")
		var body_height := CARD_BODY_HEIGHT if not hint.is_empty() else CARD_SIZE.y
		if hand == &"pistol":
			draw_texture_rect(PISTOL_ICON, Rect2(at + Vector2((CARD_SIZE.x - 68) * 0.5, (body_height - 43) * 0.5), Vector2(68, 43)), false, _ink(CAMERA_INK.lerp(WHITE, _equipment_flash)))
		else:
			var title := _fit_lines(str(ITEM_TITLES.get(hand, WeaponController.TITLES.get(hand, hand))), CARD_SIZE.x - 20, 20, 2)
			var height := _font.get_multiline_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, CARD_SIZE.x - 20, 20).y
			_wrapped(title, at + Vector2(10, (body_height - height) * 0.5 + _font.get_ascent(20)), 20, CARD_SIZE.x - 20, WHITE, HORIZONTAL_ALIGNMENT_CENTER)
		if not hint.is_empty():
			_badge(hint, at + Vector2((CARD_SIZE.x - _badge_extent(hint, 18).x) * 0.5, CARD_BODY_HEIGHT), 18)
	_draw_alpha = 1.0
	if not bool(view_state.get("has_journal", false)): return
	var journal_text := "%s — Журнал" % view_state.journal_hint
	if bool(view_state.get("journal_unread", false)): journal_text += " · Новая запись"
	var width := _font.get_string_size(journal_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	_text(journal_text, Vector2((_canvas_size.x - width) * 0.5, _canvas_size.y - 56), 22)

func status_layout(snapshot: Dictionary, driving: bool = false) -> Dictionary:
	var hand := StringName(snapshot.get("held_item", &""))
	var has_ammo := hand in [&"pistol", &"m4a1"] and not driving
	var has_light := bool(snapshot.get("has_flashlight", false))
	var reserve := int(snapshot.get("pistol_ammo", 0))
	if hand == &"m4a1":
		reserve = 0
		for rounds in snapshot.get("rifle_magazines", []): reserve += int(rounds)
	var magazine := "%02d" % int(snapshot.get("weapon_rounds", 0))
	var magazine_width := _font.get_string_size(magazine, HORIZONTAL_ALIGNMENT_LEFT, -1, 44).x
	var reserve_width := _font.get_string_size("/ %d" % reserve, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
	var ammo_width := maxf(130, magazine_width + 14 + reserve_width)
	var right := _canvas_size.x - 48
	return {"has_fuel": hand==&"flamethrower" and not driving, "has_ammo": has_ammo, "has_light": has_light, "reserve": reserve,
		"magazine": magazine, "magazine_width": magazine_width, "ammo_width": ammo_width,
		"ammo_x": right - (240 if has_light else 0) - ammo_width, "battery_x": right - 204}

func _draw_ammunition_and_light() -> void:
	var top := _canvas_size.y - LAYOUT.PRIMARY_STATUS_INSET + 8.0
	var hand := StringName(view_state.held_item)
	var layout := status_layout(view_state, player.is_driving())
	var x: float = layout.ammo_x
	if layout.has_fuel:
		var fuel_ratio:=clampf(float(view_state.get("flame_fuel_liters",0.0))/player.weapon.flame.capacity_liters,0,1)
		_text("%d%%" % roundi(fuel_ratio*100),Vector2(x,top-8),48,AMBER if fuel_ratio<.2 else WHITE)
		_text("Топливо",Vector2(x,top-56),18,MUTED)
		_text("%s — Заправить от канистры" % view_state.reload_hint,Vector2(x-100,top+27),18,MUTED)
	if layout.has_ammo:
		var rounds := int(view_state.weapon_rounds)
		var low := rounds <= maxi(1, int(WeaponController.CAPACITY.get(hand, 0)) / 4)
		_text(layout.magazine, Vector2(x, top - 8), 44, AMBER if low else WHITE.lerp(TEAL, _ammo_flash * 0.35))
		_text("/ %d" % int(layout.reserve), Vector2(x + layout.magazine_width + 14, top - 8), 28)
		if player.weapon.reload_left > 0.0:
			_text("Перезарядка…", Vector2(x, top + 27), 20, AMBER)
			var duration := player.weapon.rifle_reload_seconds if hand == &"m4a1" else player.weapon.pistol_reload_seconds
			var progress := clampf(1.0 - player.weapon.reload_left / duration, 0, 1)
			draw_line(Vector2(x, top + 38), Vector2(x + 130, top + 38), LINE, 2, true)
			draw_line(Vector2(x, top + 38), Vector2(x + 130 * progress, top + 38), AMBER, 2, true)
		elif not view_state.battery_action_busy:
			if view_state.get("reload_action", &"reload") == &"replace_battery":
				_text("%s — Батарейка" % view_state.reload_hint, Vector2(x, top + 27), 18, MUTED)
			elif rounds < int(WeaponController.CAPACITY.get(hand, 0)) and int(layout.reserve) > 0:
				_text("%s — Перезарядка" % view_state.reload_hint, Vector2(x, top + 27), 18, MUTED)
			elif rounds == 0:
				_text("Нет патронов", Vector2(x, top + 27), 18, AMBER)
	if layout.has_light:
		x = layout.battery_x
		if layout.has_ammo: draw_line(Vector2(x - 13, top - 47), Vector2(x - 13, top + 1), LINE)
		var charge := clampf(float(view_state.battery_charge), 0, 1)
		var color := AMBER if charge <= 0.15 else CAMERA_INK
		var icon_color := CAMERA_INK if view_state.flashlight_enabled else Color(CAMERA_INK, 0.58)
		_draw_flashlight_icon(Vector2(x + 20, top - 18), icon_color, view_state.flashlight_enabled)
		var hint := str(view_state.light_hint)
		var hint_width := _font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		_text(hint, Vector2(x + 20 - hint_width * 0.5, top + 27), 18, icon_color)
		var shell := Rect2(x + 62, top - 28, 42, 19)
		draw_rect(shell, Color(color, color.a * 0.11), false, 6.0)
		draw_rect(shell, color, false, 2.0)
		draw_rect(Rect2(shell.end.x, shell.position.y + 5, 4, 9), color)
		if _charge_ratio > 0.0:
			draw_rect(Rect2(shell.position + Vector2(4, 4), Vector2((shell.size.x - 8) * _charge_ratio, shell.size.y - 8)), color)
		_text("%d%%" % roundi(charge * 100), Vector2(x + 121, top - 8), 30, color)
		var notice := ""
		if view_state.battery_action_busy:
			notice = "Замена батарейки…"
		elif charge <= 0.0:
			notice = "%s — Батарейка" % view_state.reload_hint if not view_state.spare_batteries.is_empty() else "Нет батареек"
		elif Time.get_ticks_msec() < player._equipment_notice_until:
			notice = "Огнемёт занимает обе руки" if hand == &"flamethrower" else "Крепление фонаря · %s — Журнал" % view_state.journal_hint
		if not notice.is_empty():
			var width := _font.get_string_size(notice, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
			_text(notice, Vector2(_canvas_size.x - 48 - width, top + 50), 17, AMBER)

func _draw_flashlight_icon(at: Vector2, color: Color, lamp_on: bool) -> void:
	var outline := PackedVector2Array([
		Vector2(-18, -6), Vector2(1, -6), Vector2(7, -12), Vector2(14, -12),
		Vector2(14, 12), Vector2(7, 12), Vector2(1, 6), Vector2(-18, 6), Vector2(-18, -6)
	])
	var rotation := Transform2D(-PI / 4.0, Vector2.ONE * 0.81, 0.0, at)
	for index in outline.size():
		outline[index] = rotation * outline[index]
	draw_polyline(outline, Color(color, color.a * 0.12), 6.0, true)
	draw_polyline(outline, color, 2.2, true)
	draw_line(rotation * Vector2(-11, -6), rotation * Vector2(-11, 6), color, 2.2, true)
	if lamp_on:
		for direction in [-1, 0, 1]:
			draw_line(rotation * Vector2(20, direction * 8), rotation * Vector2(27, direction * 12), color, 1.7, true)
