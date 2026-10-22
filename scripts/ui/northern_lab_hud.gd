extends Control
## Presentation only: inventory, authority, damage, input and saves stay with their owners.
## Coordinates follow the supplied 2560×1440 manifest; wide screens keep edge anchors.

const WHITE := Color("efefe8")
const AMBER := Color("e2ad4d")
const TEAL := Color("84d8db")
const MUTED := Color("c3cbc9")
const LINE := Color(0.63, 0.72, 0.73, 0.26)
const FRAME_WIDTH := 1.0
const PANEL := Color(0.035, 0.05, 0.057, 0.48)
const BODY_FONT := preload("res://assets/fonts/hud/body.tres")
const HEADING_FONT := preload("res://assets/fonts/hud/heading.tres")
const LIGHT_ICON := preload("res://assets/ui/northern_lab_hud/Bonus/flashlight_icon_4x.png")
const PISTOL_ICON := preload("res://assets/ui/northern_lab_hud/Bonus/pistol_icon_4x.png")
const MARKER := preload("res://assets/ui/northern_lab_hud/Bonus/teammate_world_marker_4x.png")
const HEALTH_ART := preload("res://assets/ui/northern_lab_hud/PNG_4x/07_health_radiation.png")
const BATTERY_ART := preload("res://assets/ui/northern_lab_hud/PNG_4x/11_flashlight_charge.png")
const CARD_SIZE := Vector2(178, 108)
const CARD_FRAME_PADDING := 8.0
const CARD_GAP := 12.0 + CARD_FRAME_PADDING * 2.0
const CARD_TOP_MARGIN := 210.0
const CARD_BODY_HEIGHT := 76.0
const PARALLAX := preload("res://scripts/ui/hud_parallax.gd")
const LAYOUT := preload("res://scripts/ui/hud_layout.gd")
const EDGE_INSET := 16.0
const ITEM_TITLES := {&"flamethrower":"Огнемёт",&"m4a1": "M4A1", &"kitchen_knife": "Нож", &"fuel_can": "Канистра",
	&"fuse": "Предохранитель", &"seed_packet": "Семена"}

var player: GamePlayer
var view_state: Dictionary = {}
var compass_heading := 0.0
var teammate: GamePlayer
var _font: Font = BODY_FONT
var _frame_style := StyleBoxFlat.new()
var _badge_metrics_cache: Dictionary = {}
var _elapsed := 0.0
var _legacy_adopted := false
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
var _objective_height := 0.0
var _objective_from_height := 0.0
var _objective_width := 440.0
var _objective_from_width := 440.0
var _equipment_view: Array = []
var _equipment_pending: Array = []
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

static func motion_curve(value: float) -> float:
	# Smoothstep: zero velocity at both ends, no overshoot, independent of frame rate.
	var t := clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func _ready() -> void:
	player = get_parent().get_parent() as GamePlayer
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	hide()
	get_viewport().size_changed.connect(_layout)
	_layout()

func _layout() -> void:
	var viewport_size := get_viewport_rect().size
	_layout_scale = LAYOUT.scale_for(get_viewport())
	_canvas_size = viewport_size / _layout_scale
	scale = Vector2.ONE * _layout_scale
	size = _canvas_size
	queue_redraw()

func _process(delta: float) -> void:
	if not is_instance_valid(player) or player.survival == null or player.weapon == null:
		return
	if not _legacy_adopted:
		# Preserve visible/text properties: weapon input and existing interactions use them.
		# Only their old rendering is replaced, never their gameplay state.
		for control: CanvasItem in [player.crosshair.get_node("CrosshairLabel"),
			player.interaction_prompt_label, player.battery_label,
			player.weapon.get_node("HUD/WeaponLabel"), player.survival._hud]:
			control.self_modulate.a = 0.0
		_legacy_adopted = true
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
	_elapsed += delta
	if view_state.is_empty() or _elapsed >= 0.1:
		_elapsed = 0.0
		refresh_state()
	var forward := -player.camera.global_basis.z
	compass_heading = fposmod(rad_to_deg(atan2(forward.x, -forward.z)), 360.0)
	_update_parallax(forward, delta)
	_update_animations(delta)
	queue_redraw()

func _update_parallax(forward: Vector3, delta: float) -> void:
	var camera_id := player.camera.get_instance_id()
	if camera_id != _parallax_camera_id or player.global_position.distance_squared_to(_parallax_position) > 9.0:
		_parallax.reset()
	_parallax_camera_id = camera_id
	_parallax_position = player.global_position
	_parallax.sample(forward, delta)

func panel_offset(edge_direction: Vector2 = Vector2.ZERO) -> Vector2:
	return _parallax.offset + edge_direction * EDGE_INSET

func get_parallax_offset_pixels() -> Vector2:
	return _parallax.offset * _layout_scale if visible else Vector2.ZERO

func _update_animations(delta: float) -> void:
	_reveal = move_toward(_reveal, 1.0, delta / 0.20)
	modulate.a = motion_curve(_reveal)
	var incoming := player.interaction_prompt_label.text.strip_edges() if player.interaction_prompt_label.visible else ""
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
		_objective_height = _objective_view.rect.size.y
		_objective_width = _objective_view.rect.size.x
		_objective_alpha = 1.0
		_objective_phase = 0
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
	_objective_time += delta
	match _objective_phase:
		1:
			_objective_alpha = _objective_from_alpha * (1.0 - motion_curve(_objective_time / 0.08))
			if _objective_time >= 0.08:
				_objective_view = _objective_pending
				_objective_from_height = _objective_height
				_objective_from_width = _objective_width
				_objective_phase = 2
				_objective_time = 0.0
		2:
			_objective_height = lerpf(_objective_from_height, _objective_view.rect.size.y, motion_curve(_objective_time / 0.18))
			_objective_width = lerpf(_objective_from_width, _objective_view.rect.size.x, motion_curve(_objective_time / 0.18))
			if _objective_time >= 0.18:
				_objective_phase = 3
				_objective_time = 0.0
		3:
			_objective_alpha = motion_curve(_objective_time / 0.14)
			if _objective_time >= 0.14: _objective_phase = 0

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
	return player.is_local_player() and not player.survival.dead \
		and not player.is_debug_free_camera_active() and not player._is_journal_open() \
		and not player.is_sleeping_in_bunk() and not get_node("/root/GameMenu").is_menu_open()

func refresh_state() -> void:
	var journal := get_node("/root/QuestJournal")
	view_state = player.get_inventory_snapshot()
	view_state["health"] = player.survival.health
	view_state["max_health"] = player.survival.max_health
	# The game models radiation as a 0–100 exposure gauge, not a measured dose.
	view_state["radiation"] = player.survival.radiation
	view_state["quest"] = journal.get_hud_summary()
	view_state["light_hint"] = _action_hint(&"flashlight")
	view_state["attack_hint"] = _action_hint(&"weapon_attack")
	view_state["journal_hint"] = _action_hint(&"journal")
	view_state["reload_hint"] = _action_hint(&"replace_battery")
	view_state["reload_action"] = player.get_reload_or_battery_action()
	view_state["battery_action_busy"] = player._battery_action_busy
	var world := get_tree().get_first_node_in_group("network_gameplay_controller")
	view_state["arrival"] = world != null and world.has_method("is_waiting_for_arrival") and world.is_waiting_for_arrival()
	var objective := str(view_state.quest)
	if not _last_objective.is_empty() and objective != _last_objective:
		_objective_pending = objective_layout(view_state.quest)
		if _animated_state_initialized and _objective_phase != 1:
			_objective_phase = 1
			_objective_time = 0.0
			_objective_from_alpha = _objective_alpha
	_last_objective = objective
	var equipment := "%s/%s" % [view_state.held_item, view_state.has_flashlight]
	if not _last_equipment.is_empty() and equipment != _last_equipment:
		_equipment_flash = 1.0
		_equipment_pending = equipment_layout(view_state)
		if _animated_state_initialized and _equipment_phase != 1:
			_equipment_phase = 1
			_equipment_time = 0.0
			_equipment_from_alpha = _equipment_alpha
	elif _equipment_phase == 0:
		# Rebinding and toggling a light update in place, without replaying a reveal.
		_equipment_view = equipment_layout(view_state)
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
	return str(service.get_action_hint(action)).trim_prefix("[").trim_suffix("]")

func _draw() -> void:
	if view_state.is_empty() or not is_instance_valid(player):
		return
	_draw_compass()
	if player.crosshair.visible:
		draw_circle(_canvas_size * 0.5, 3.5, Color(0, 0, 0, 0.85))
		draw_circle(_canvas_size * 0.5, 2.5, WHITE)
	draw_set_transform(panel_offset(Vector2(1, 1)))
	_draw_objectives()
	draw_set_transform(panel_offset(Vector2(-1, 1)))
	_draw_teammate()
	draw_set_transform(panel_offset())
	_draw_interaction()
	draw_set_transform(panel_offset(Vector2(1, -1)))
	_draw_health()
	draw_set_transform(panel_offset(Vector2(0, -1)))
	_draw_equipment()
	draw_set_transform(panel_offset(Vector2(-1, -1)))
	_draw_ammunition_and_light()
	draw_set_transform(Vector2.ZERO)

func _text(value: String, at: Vector2, font_size: int = 24, color: Color = WHITE, width: float = -1.0, heading: bool = false) -> void:
	var font: Font = HEADING_FONT if heading else _font
	# A tight vertical shadow supports the high-resolution glyphs on bright scenery.
	draw_string(font, at + Vector2(0, 1), value, HORIZONTAL_ALIGNMENT_LEFT, width, font_size, Color(0, 0, 0, 0.85 * _draw_alpha))
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
	var result := {"rect": Rect2(44, 88, 440, 58), "empty": tasks.is_empty(),
		"empty_label": str(quest.get("empty_label", "НЕТ АКТИВНЫХ ЗАДАЧ")), "rows": [], "footer": "", "title": ""}
	if tasks.is_empty():
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
		result.rows.append({"text": content, "y": y})
		abbreviated = abbreviated or content != str(task)
		y += _font.get_multiline_string_size(content, HORIZONTAL_ALIGNMENT_LEFT, 370, 24).y + 10
	if tasks.size() > 2 or abbreviated:
		result.footer = "ЕЩЁ %d" % (tasks.size() - 2) if tasks.size() > 2 else "ПОДРОБНЕЕ"
		result.footer_y = y + 4
		y += _font.get_height(18) + 4
	result.rect.size.y = y + 10
	return result

func _draw_objectives() -> void:
	# Arrival already has its own lobby card; story objectives begin on the base.
	if bool(view_state.get("arrival", false)):
		return
	var quest: Dictionary = view_state.quest
	var day := int(quest.get("day", 0))
	if day <= 0 or _objective_view.is_empty(): return
	var heading := "ДЕНЬ %02d" % day
	if player.global_position.y < -12.0:
		heading += "  /  ПОДЗЕМНЫЙ КОМПЛЕКС"
	_text(heading, Vector2(48, 60), 21, MUTED, -1, true)
	var layout := _objective_view
	var panel: Rect2 = layout.rect
	panel.size.y = _objective_height
	panel.size.x = _objective_width
	_panel(panel, PANEL, LINE)
	_draw_alpha = _objective_alpha
	if layout.empty:
		draw_circle(panel.position + Vector2(24, 29), 3, _ink(TEAL))
		_text(layout.empty_label, panel.position + Vector2(38, 29 + HEADING_FONT.get_ascent(18) - HEADING_FONT.get_height(18) * 0.5), 18, MUTED, -1, true)
	else:
		_text("ТЕКУЩАЯ ЗАДАЧА", panel.position + Vector2(26, 18 + HEADING_FONT.get_ascent(18)), 18, MUTED, -1, true)
		draw_rect(Rect2(panel.position + Vector2(0, layout.title_y + 4), Vector2(1, 24)), _ink(AMBER))
		_wrapped(layout.title, panel.position + Vector2(26, layout.title_y + _font.get_ascent(28)), 28, 388, AMBER)
		for row in layout.rows:
			draw_circle(panel.position + Vector2(29, row.y + _font.get_ascent(24) - 7), 2, _ink(MUTED))
			_wrapped(row.text, panel.position + Vector2(46, row.y + _font.get_ascent(24)), 24, 370, WHITE)
		if not str(layout.footer).is_empty():
			_text(layout.footer, panel.position + Vector2(26, layout.footer_y + _font.get_ascent(18)), 18, MUTED)
	_draw_alpha = 1.0

func compass_layout() -> Rect2:
	# Preserve room for the day/objective header on narrow and 4:3 screens.
	var width := minf(840, maxf(280, _canvas_size.x - 1080))
	return Rect2((_canvas_size.x - width) * 0.5, 38, width, 64)

func _draw_compass() -> void:
	var center := _canvas_size.x * 0.5
	var rect := compass_layout()
	var left := rect.position.x
	draw_line(Vector2(left, 64), Vector2(rect.end.x, 64), LINE, 1.0, true)
	var labels := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	for tick in range(-32, 65):
		var degrees := tick * 11.25
		var x := center + (degrees - compass_heading) * 3.8
		if x < left + 24 or x > rect.end.x - 24:
			continue
		var major := posmod(tick, 4) == 0
		draw_line(Vector2(x, 52 if major else 57), Vector2(x, 71 if major else 69), LINE, 1, true)
		if major:
			var label: String = labels[posmod(floori(tick / 4.0), 8)]
			var text_width := HEADING_FONT.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 21).x
			_text(label, Vector2(x - text_width * 0.5, 96), 21, MUTED, -1, true)
	draw_colored_polygon(PackedVector2Array([Vector2(center - 8, 38), Vector2(center + 8, 38), Vector2(center, 53)]), AMBER)

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
	if not player.camera.is_position_behind(world_point):
		var screen_point := player.camera.unproject_position(world_point)
		if get_viewport_rect().grow(-30).has_point(screen_point):
			draw_texture_rect(MARKER, Rect2(screen_point / _layout_scale - Vector2(16, 16), Vector2(32, 32)), false, _ink(WHITE))
	_draw_alpha = 1.0

func interaction_layout(source: String) -> Dictionary:
	var prompt := source.strip_edges()
	var key := ""
	# Only explicit actionable hints get a keycap. Informational/blocked hints stay informational.
	if prompt.begins_with("[") and prompt.contains("]"):
		var end := prompt.find("]")
		key = prompt.substr(1, end - 1)
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
	return {"rect": Rect2(at, Vector2(width, height)), "text": prompt, "key": key, "key_size": key_size, "indent": indent, "text_width": width - indent * 2}

func _draw_interaction() -> void:
	if _prompt_text.is_empty() or _prompt_alpha <= 0.0:
		return
	var layout := interaction_layout(_prompt_text)
	var rect: Rect2 = layout.rect
	_draw_alpha = _prompt_alpha
	_panel(rect, Color(0.025, 0.04, 0.045, 0.52), LINE)
	var key := str(layout.key)
	if not key.is_empty():
		draw_line(rect.position + Vector2(0, rect.size.y * 0.5 - 7), rect.position + Vector2(0, rect.size.y * 0.5 + 7), _ink(Color(AMBER, 0.75)), FRAME_WIDTH, true)
		_badge(key, rect.position + Vector2(10, (rect.size.y - layout.key_size.y) * 0.5), 22)
	var text_height := _font.get_multiline_string_size(str(layout.text), HORIZONTAL_ALIGNMENT_LEFT, layout.text_width, 24).y
	_wrapped(str(layout.text), rect.position + Vector2(float(layout.indent), (rect.size.y - text_height) * 0.5 + _font.get_ascent(24)), 24, layout.text_width, WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_draw_alpha = 1.0

func _draw_health() -> void:
	var top := _canvas_size.y - 196
	draw_line(Vector2(46, top + 4), Vector2(46, top + 150), LINE)
	_text("СОСТОЯНИЕ", Vector2(73, top + 17), 19, MUTED, -1, true)
	var hp := float(view_state.health)
	var ratio := clampf(hp / float(view_state.max_health), 0, 1)
	var color := AMBER if ratio < 0.3 else WHITE
	_text(str(ceili(hp)), Vector2(73, top + 84), 58, color)
	draw_rect(Rect2(169, top + 57, 232, 15), Color(0.14, 0.17, 0.18, 0.8))
	draw_rect(Rect2(171, top + 58, 228 * _health_ratio, 12), color)
	draw_line(Vector2(169, top + 75), Vector2(401, top + 75), LINE)
	# Reuse the supplied radiation pictogram, not the baked sample numbers.
	draw_texture_rect_region(HEALTH_ART, Rect2(72, top + 107, 38, 38), Rect2(128, 424, 144, 140))
	var radiation := float(view_state.radiation)
	_text("%.0f%%" % radiation, Vector2(122, top + 129), 23, AMBER if radiation >= player.survival.radiation_damage_threshold else WHITE)
	if radiation >= player.survival.radiation_damage_threshold:
		_text("Покиньте зону", Vector2(72, top + 172), 17, AMBER)

func equipment_layout(snapshot: Dictionary) -> Array:
	var cards: Array = []
	var hand := StringName(snapshot.get("held_item", &""))
	if snapshot.get("has_flashlight", false):
		cards.append({"item": &"flashlight", "hint": str(snapshot.get("light_hint", "F"))})
	if hand not in [&"", &"flashlight"]:
		cards.append({"item": hand, "hint": str(snapshot.get("attack_hint", "ЛКМ")) if WeaponController.TYPES.has(hand) or hand==&"flamethrower" else ""})
	var width := cards.size() * CARD_SIZE.x + maxf(0, cards.size() - 1) * CARD_GAP
	for index in cards.size():
		cards[index].rect = Rect2(Vector2((_canvas_size.x - width) * 0.5 + index * (CARD_SIZE.x + CARD_GAP), _canvas_size.y - CARD_TOP_MARGIN), CARD_SIZE)
		cards[index].frame = cards[index].rect.grow(CARD_FRAME_PADDING)
	return cards

func _draw_equipment() -> void:
	_draw_alpha = _equipment_alpha
	for card in _equipment_view:
		# Re-anchor on viewport changes even if the inventory has not changed.
		var index := _equipment_view.find(card)
		var width := _equipment_view.size() * CARD_SIZE.x + maxf(0, _equipment_view.size() - 1) * CARD_GAP
		var at := Vector2((_canvas_size.x - width) * 0.5 + index * (CARD_SIZE.x + CARD_GAP), _canvas_size.y - CARD_TOP_MARGIN)
		var hand := StringName(card.item)
		var is_light := hand == &"flashlight"
		var active := bool(view_state.flashlight_enabled) if is_light else true
		var hint := str(card.hint).replace(" / Create", "")
		var body_height := CARD_BODY_HEIGHT if not hint.is_empty() else CARD_SIZE.y
		var frame := Rect2(at, CARD_SIZE).grow(CARD_FRAME_PADDING)
		var fill := PANEL.blend(Color(TEAL, 0.035 + _equipment_flash * 0.04))
		_panel(frame, fill, Color(TEAL, 0.34) if active else LINE)
		if is_light:
			draw_texture_rect(LIGHT_ICON, Rect2(at + Vector2((CARD_SIZE.x - 100) * 0.5, (body_height - 45) * 0.5), Vector2(100, 45)), false, _ink(WHITE))
		elif hand == &"pistol":
			draw_texture_rect(PISTOL_ICON, Rect2(at + Vector2((CARD_SIZE.x - 86) * 0.5, (body_height - 55) * 0.5), Vector2(86, 55)), false, _ink(WHITE))
		else:
			var title := _fit_lines(str(ITEM_TITLES.get(hand, hand)), CARD_SIZE.x - 20, 20, 2)
			var height := _font.get_multiline_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, CARD_SIZE.x - 20, 20).y
			_wrapped(title, at + Vector2(10, (body_height - height) * 0.5 + _font.get_ascent(20)), 20, CARD_SIZE.x - 20, WHITE, HORIZONTAL_ALIGNMENT_CENTER)
		if not hint.is_empty():
			_badge(hint, at + Vector2((CARD_SIZE.x - _badge_extent(hint, 18).x) * 0.5, CARD_BODY_HEIGHT), 18)
	_draw_alpha = 1.0
	var journal_text := "%s — Журнал" % view_state.journal_hint
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
	var magazine_width := _font.get_string_size(magazine, HORIZONTAL_ALIGNMENT_LEFT, -1, 56).x
	var reserve_width := _font.get_string_size("/ %d" % reserve, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
	var ammo_width := maxf(130, magazine_width + 14 + reserve_width)
	var right := _canvas_size.x - 48
	return {"has_fuel": hand==&"flamethrower" and not driving, "has_ammo": has_ammo, "has_light": has_light, "reserve": reserve,
		"magazine": magazine, "magazine_width": magazine_width, "ammo_width": ammo_width,
		"ammo_x": right - (154 if has_light else 0) - ammo_width, "battery_x": right - 128}

func _draw_ammunition_and_light() -> void:
	var top := _canvas_size.y - 90
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
		_text(layout.magazine, Vector2(x, top - 8), 56, AMBER if low else WHITE.lerp(TEAL, _ammo_flash * 0.35))
		_text("/ %d" % int(layout.reserve), Vector2(x + layout.magazine_width + 14, top - 8), 28)
		if player.weapon.reload_left > 0.0:
			_text("Перезарядка…", Vector2(x, top + 27), 20, AMBER)
			var duration := player.weapon.rifle_reload_seconds if hand == &"m4a1" else player.weapon.pistol_reload_seconds
			var progress := clampf(1.0 - player.weapon.reload_left / duration, 0, 1)
			draw_line(Vector2(x, top + 38), Vector2(x + 130, top + 38), LINE, 2, true)
			draw_line(Vector2(x, top + 38), Vector2(x + 130 * progress, top + 38), AMBER, 2, true)
		elif bool(view_state.get("battery_action_busy", false)):
			_text("Замена батарейки…", Vector2(x, top + 27), 18, MUTED)
		elif view_state.get("reload_action", &"reload") == &"replace_battery":
			_text("%s — Батарейка" % view_state.reload_hint, Vector2(x, top + 27), 18, MUTED)
		elif rounds < int(WeaponController.CAPACITY.get(hand, 0)) and int(layout.reserve) > 0:
			_text("%s — Перезарядка" % view_state.reload_hint, Vector2(x, top + 27), 18, MUTED)
		elif rounds == 0:
			_text("Нет патронов", Vector2(x, top + 27), 18, AMBER)
	if layout.has_light:
		x = layout.battery_x
		if layout.has_ammo: draw_line(Vector2(x - 13, top - 47), Vector2(x - 13, top + 1), LINE)
		# Battery shell from the reference; its fill and percentage follow the inventory.
		draw_texture_rect_region(BATTERY_ART, Rect2(x + 9, top - 45, 26, 46), Rect2(100, 32, 104, 184))
		draw_rect(Rect2(x + 21, top - 23, 8, 21), Color("0e1214"))
		var charge := clampf(float(view_state.battery_charge), 0, 1)
		var color := AMBER if charge <= 0.15 else WHITE
		draw_rect(Rect2(x + 21, top - 2 - _charge_ratio * 21, 8, _charge_ratio * 21), color)
		var percentage := "%d%%" % roundi(charge * 100)
		var percentage_width := _font.get_string_size(percentage, HORIZONTAL_ALIGNMENT_LEFT, -1, 25).x
		_text(percentage, Vector2(_canvas_size.x - 48 - percentage_width, top - 10), 25, color)
		var notice := ""
		if charge <= 0.0:
			notice = "%s — Батарейка" % view_state.reload_hint if not view_state.spare_batteries.is_empty() else "Нет батареек"
		elif player.needs_flashlight_shake():
			notice = "Встряхните фонарь"
		elif Time.get_ticks_msec() < player._equipment_notice_until:
			notice = "Крепление фонаря · %s — Журнал" % view_state.journal_hint
		if not notice.is_empty():
			var width := _font.get_string_size(notice, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
			_text(notice, Vector2(_canvas_size.x - 48 - width, top + 50), 17, AMBER)
