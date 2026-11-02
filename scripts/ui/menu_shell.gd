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
	content.offset_left = 72 if enabled else 99
	content.offset_top = 141 if enabled else 96
	content.offset_bottom = -123 if enabled else -96

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
	busy = true
	_epoch += 1
	var epoch := _epoch
	var origin := content.position.x
	var duration := .16 if compact else .30
	if is_instance_valid(presentation) and presentation.is_visible_in_tree():
		duration = .55
	_motion = create_tween().set_parallel(true)
	_motion.tween_property(content, "modulate:a", 0.0, duration).set_custom_interpolator(NorthernMenuStyle.ease)
	_motion.tween_property(content, "position:x", origin - 18.0, duration).set_custom_interpolator(NorthernMenuStyle.ease)
	_motion.tween_property(header, "modulate:a", 0.0, duration).set_custom_interpolator(NorthernMenuStyle.ease)
	_motion.tween_property(footer, "modulate:a", 0.0, duration).set_custom_interpolator(NorthernMenuStyle.ease)
	if closing:
		_motion.tween_property(shade, "modulate:a", 0.0, duration).set_custom_interpolator(NorthernMenuStyle.ease)
	if is_instance_valid(presentation) and presentation.has_method("animate_out"):
		presentation.animate_out(_motion, duration)
	await _motion.finished
	if epoch != _epoch: return
	content.position.x = origin
	callback.call()
	# Scene changes/force_close_menu cancel the old sequence before the next entry.
	if epoch != _epoch or not is_inside_tree(): return
	if closing:
		busy = false
		return
	_motion = create_tween().set_parallel(true)
	_enter(_motion, .30 if compact else .52, not compact)
	await _motion.finished
	if epoch == _epoch: busy = false

func disappear(callback: Callable) -> void:
	transition(callback, false, true)

func _enter(motion: Tween, duration: float, stagger: bool) -> void:
	content.modulate.a = 0.0
	content.position.x += 22.0
	motion.tween_property(content, "modulate:a", 1.0, duration).set_custom_interpolator(NorthernMenuStyle.ease)
	motion.tween_property(content, "position:x", content.position.x - 22.0, duration).set_custom_interpolator(NorthernMenuStyle.ease)
	motion.tween_property(header, "modulate:a", 1.0, duration).set_custom_interpolator(NorthernMenuStyle.ease)
	motion.tween_property(footer, "modulate:a", 1.0, duration).set_custom_interpolator(NorthernMenuStyle.ease)
	if stagger: _stagger(motion)

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
		motion.tween_property(item, "modulate:a", 1.0, .38).set_delay(index * .04).set_custom_interpolator(NorthernMenuStyle.ease)

func appear() -> void:
	cancel_transition()
	busy = true
	var epoch := _epoch
	header.modulate.a = 0.0
	footer.modulate.a = 0.0
	shade.modulate.a = 0.0
	_motion = create_tween().set_parallel(true)
	_motion.tween_property(shade, "modulate:a", 1.0, .5).set_custom_interpolator(NorthernMenuStyle.ease)
	_enter(_motion, .6, true)
	_motion.finished.connect(func():
		if epoch == _epoch: busy = false
	)

func cancel_transition() -> void:
	_epoch += 1
	if _motion != null and _motion.is_valid(): _motion.kill()
	busy = false
	content.modulate.a = 1.0
	content.offset_left = 72 if top_rail.visible else 99
	header.modulate.a = 1.0
	footer.modulate.a = 1.0
	shade.modulate.a = 1.0
	for item in _stagger_items:
		if is_instance_valid(item): item.modulate.a = 1.0
	_stagger_items.clear()
