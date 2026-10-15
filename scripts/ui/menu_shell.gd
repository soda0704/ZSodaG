class_name NorthernMenuShell
extends Control

var content: Control
var header: HBoxContainer
var footer: HBoxContainer
var shade: ColorRect
var top_rail: ColorRect
var bottom_rail: ColorRect
var video: VideoStreamPlayer
var busy := false
var _epoch := 0
var _motion: Tween

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

func transition(callback: Callable, compact: bool = false) -> void:
	if busy:
		return
	busy = true
	_epoch += 1
	var epoch := _epoch
	var tween := create_tween().set_parallel(true)
	_motion = tween
	var origin := content.position.x
	var duration := 0.12 if compact else 0.20
	tween.tween_property(content, "modulate:a", 0.0, duration).set_custom_interpolator(NorthernMenuStyle.ease)
	tween.tween_property(content, "position:x", origin - 12.0, duration).set_custom_interpolator(NorthernMenuStyle.ease)
	tween.tween_property(header, "modulate:a", 0.65, duration)
	tween.tween_property(footer, "modulate:a", 0.42, duration)
	await tween.finished
	if epoch != _epoch:
		return
	content.position.x = origin
	callback.call()
	# Closing a menu or replacing its scene can cancel this transition in callback.
	if epoch != _epoch or not is_inside_tree():
		return
	content.modulate.a = 0
	content.position.x += 15
	var enter := create_tween().set_parallel(true)
	_motion = enter
	enter.tween_property(content, "modulate:a", 1.0, 0.20 if compact else 0.32).set_custom_interpolator(NorthernMenuStyle.ease)
	enter.tween_property(content, "position:x", content.position.x - 15, 0.24 if compact else 0.40).set_custom_interpolator(NorthernMenuStyle.ease)
	enter.tween_property(header, "modulate:a", 1.0, 0.25)
	enter.tween_property(footer, "modulate:a", 1.0, 0.30)
	if not compact:
		_stagger(enter)
	await enter.finished
	if epoch == _epoch:
		busy = false

func _stagger(tween: Tween) -> void:
	var items: Array[Node] = []
	for navigation in content.find_children("Navigation", "Container", true, false):
		if navigation.is_visible_in_tree():
			items.append_array(navigation.get_children())
	for row in content.find_children("*", "HBoxContainer", true, false):
		if row.is_visible_in_tree() and row.get_script() == preload("res://scripts/ui/menu_setting_row.gd"):
			items.append(row)
	for index in mini(items.size(), 7):
		var item := items[index] as Control
		item.modulate.a = 0
		tween.tween_property(item, "modulate:a", 1.0, 0.24).set_delay(index * 0.025).set_custom_interpolator(NorthernMenuStyle.ease)

func appear() -> void:
	cancel_transition()
	content.modulate.a = 0
	_motion = create_tween()
	_motion.tween_property(content, "modulate:a", 1.0, 0.30).set_custom_interpolator(NorthernMenuStyle.ease)

func cancel_transition() -> void:
	_epoch += 1
	if _motion != null and _motion.is_valid():
		_motion.kill()
	busy = false
	content.modulate.a = 1
	content.offset_left = 72 if top_rail.visible else 99
	header.modulate.a = 1
	footer.modulate.a = 1
	for navigation in content.find_children("Navigation", "Container", true, false):
		for item in navigation.get_children():
			if item is Control:
				item.modulate.a = 1
	for row in content.find_children("*", "HBoxContainer", true, false):
		if row.get_script() == preload("res://scripts/ui/menu_setting_row.gd"):
			row.modulate.a = 1
