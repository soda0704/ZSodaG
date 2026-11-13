class_name NorthernMenuShell
extends Control

var content: Control
var header: HBoxContainer
var footer: HBoxContainer
var shade: ColorRect
var top_rail: ColorRect
var bottom_rail: ColorRect
var video: VideoStreamPlayer
var presentation: Control
var busy := false
var _epoch := 0
var _motion: Tween
var _stagger_items: Array[Control] = []
var _rest_content_x := 0.0
var _has_motion_origin := false

func _ready() -> void:
	NorthernMenuStyle.fill(self)
	shade = $Shade
	content = $Content
	top_rail = $TopRail
	bottom_rail = $BottomRail
	header = $TopRail/Row
	footer = $BottomRail/Row

func rails(enabled: bool) -> void:
	top_rail.visible = enabled
	bottom_rail.visible = enabled
	content.offset_left = 88
	content.offset_top = 102 if enabled else 76
	content.offset_bottom = -104 if enabled else -88

func clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

func replace(view: Control) -> void:
	clear(content)
	content.add_child(view)
	NorthernMenuStyle.fill(view)

func transition(callback: Callable, compact: bool = false, closing: bool = false) -> void:
	if busy: return
	if NorthernMenuStyle.keyboard_navigation:
		cancel_transition()
		callback.call()
		return
	busy = true
	_epoch += 1
	var epoch := _epoch
	var origin := content.position.x
	_rest_content_x = origin
	_has_motion_origin = true
	var duration := .12 if compact else NorthernMenuStyle.EXIT_SECONDS
	if is_instance_valid(presentation) and presentation.is_visible_in_tree():
		duration = .24
	_motion = create_tween().set_parallel(true)
	_motion.tween_property(content, "modulate:a", 0.0, duration).set_custom_interpolator(NorthernMenuStyle.ease)
	if not NorthernMenuStyle.reduced_motion:
		_motion.tween_property(content, "position:x", origin + 8.0, duration).set_custom_interpolator(NorthernMenuStyle.ease)
	_motion.tween_property(header, "modulate:a", 0.0, duration).set_custom_interpolator(NorthernMenuStyle.ease)
	_motion.tween_property(footer, "modulate:a", 0.0, duration).set_custom_interpolator(NorthernMenuStyle.ease)
	if closing:
		_motion.tween_property(shade, "modulate:a", 0.0, duration).set_custom_interpolator(NorthernMenuStyle.ease)
	if is_instance_valid(presentation) and presentation.has_method("animate_out"):
		presentation.animate_out(_motion, duration)
	await _motion.finished
	if epoch != _epoch: return
	content.position.x = origin
	_has_motion_origin = false
	callback.call()
	# Scene changes/force_close_menu cancel the old sequence before the next entry.
	if epoch != _epoch or not is_inside_tree(): return
	if closing:
		busy = false
		return
	_motion = create_tween().set_parallel(true)
	_enter(_motion, .18 if compact else NorthernMenuStyle.ENTER_SECONDS, not compact)
	await _motion.finished
	if epoch == _epoch: busy = false

func disappear(callback: Callable) -> void:
	transition(callback, false, true)

func _enter(motion: Tween, duration: float, stagger: bool) -> void:
	_rest_content_x = content.position.x
	_has_motion_origin = true
	content.modulate.a = 0.0
	if not NorthernMenuStyle.reduced_motion: content.position.x += 12.0
	motion.tween_property(content, "modulate:a", 1.0, duration).set_custom_interpolator(NorthernMenuStyle.ease)
	if not NorthernMenuStyle.reduced_motion:
		motion.tween_property(content, "position:x", content.position.x - 12.0, duration).set_custom_interpolator(NorthernMenuStyle.ease)
	motion.tween_property(header, "modulate:a", 1.0, duration).set_custom_interpolator(NorthernMenuStyle.ease)
	motion.tween_property(footer, "modulate:a", 1.0, duration).set_custom_interpolator(NorthernMenuStyle.ease)
	motion.finished.connect(func(): _has_motion_origin = false)
	if stagger and not NorthernMenuStyle.reduced_motion: _stagger(motion)

func _stagger(motion: Tween) -> void:
	_stagger_items.clear()
	for navigation in content.find_children("Navigation", "Container", true, false):
		if navigation.is_visible_in_tree():
			for child in navigation.get_children():
				if child is Control: _stagger_items.append(child)
	for row in content.find_children("*", "HBoxContainer", true, false):
		if row.is_visible_in_tree() and row.get_script() == preload("res://scripts/ui/menu_setting_row.gd"):
			_stagger_items.append(row)
	for page in content.get_children():
		for child in page.get_children():
			if child is BaseButton and child.is_visible_in_tree() and child not in _stagger_items:
				_stagger_items.append(child)
	for index in mini(_stagger_items.size(), 7):
		var item := _stagger_items[index]
		item.modulate.a = 0.0
		motion.tween_property(item, "modulate:a", 1.0, .16).set_delay(index * NorthernMenuStyle.STAGGER_SECONDS).set_custom_interpolator(NorthernMenuStyle.ease)

func appear() -> void:
	cancel_transition()
	if NorthernMenuStyle.keyboard_navigation: return
	busy = true
	var epoch := _epoch
	header.modulate.a = 0.0
	footer.modulate.a = 0.0
	shade.modulate.a = 0.0
	_motion = create_tween().set_parallel(true)
	_motion.tween_property(shade, "modulate:a", 1.0, .28).set_custom_interpolator(NorthernMenuStyle.ease)
	_enter(_motion, .24, true)
	_motion.finished.connect(func():
		if epoch == _epoch: busy = false
	)

func cancel_transition() -> void:
	_epoch += 1
	if _motion != null and _motion.is_valid(): _motion.kill()
	if _has_motion_origin:
		content.position.x = _rest_content_x
		_has_motion_origin = false
	busy = false
	content.modulate.a = 1.0
	content.offset_left = 88
	header.modulate.a = 1.0
	footer.modulate.a = 1.0
	shade.modulate.a = 1.0
	for item in _stagger_items:
		if is_instance_valid(item): item.modulate.a = 1.0
	_stagger_items.clear()
