extends Control
@export var atlas: JournalAtlas
@onready var plan: TextureRect = $MapScroll/Plan
@onready var title: Label = $Title
@onready var status: Label = $Status
@onready var empty: Label = $Empty
@onready var marker: Polygon2D = $MapScroll/Plan/Player
@onready var mate_marker: Polygon2D = $MapScroll/Plan/Teammate
@onready var scroll: ScrollContainer = $MapScroll
var zoom := 1.0
var _panning := false
var selected := 0
var visited: Array = []
var _buttons: Array[Node] = []
var _elapsed := 0.0
var actor: GamePlayer

func _ready() -> void:
	_buttons = $Levels.get_children()
	for i in _buttons.size(): _buttons[i].pressed.connect(select_floor.bind(i))
	$Zoom/Minus.pressed.connect(change_zoom.bind(-1))
	$Zoom/Plus.pressed.connect(change_zoom.bind(1))
	scroll.gui_input.connect(_pan_input)
	visibility_changed.connect(_on_visibility_changed)
	select_floor(0)

func _on_visibility_changed() -> void:
	if not is_visible_in_tree(): return
	actor = get_tree().get_first_node_in_group("local_player") as GamePlayer
	if actor != null:
		var level := level_for(actor.global_position)
		if visited.has(level): select_floor(level)

func update_visited(next: Array) -> void:
	visited = next.duplicate()
	select_floor(selected)

func level_for(position: Vector3) -> int:
	var nearest := -1
	var distance := 7.0
	for i in atlas.floors.size():
		var floor_data := atlas.floors[i]
		var gap := absf(position.y - floor_data.elevation)
		if i == 6 and position.y < floor_data.elevation + 7: gap = 0.0
		if gap < distance and floor_data.world_rect.grow(2).has_point(Vector2(position.x,position.z)):
			nearest = i
			distance = gap
	return nearest

func select_floor(index: int) -> void:
	if selected != index:
		zoom = 1.0
		plan.custom_minimum_size = Vector2(510,566)
		scroll.scroll_horizontal = 0
		scroll.scroll_vertical = 0
	selected = clampi(index, 0, atlas.floors.size()-1)
	var known := visited.has(selected)
	var data := atlas.floors[selected]
	title.text = data.title if known else "Неизвестный уровень"
	status.text = "%s  /  %s" % [data.level_label, "СХЕМА МАРШРУТА" if selected == 6 else "ПЛАН УРОВНЯ"] if known else "ЗАПИСЕЙ НЕТ"
	plan.texture = data.plan if known else null
	empty.visible = not known
	for i in _buttons.size():
		_buttons[i].text = "???" if i == 6 and not visited.has(i) else "%s   %s" % [atlas.floors[i].level_label, atlas.floors[i].title if visited.has(i) else "— — —"]
		_buttons[i].button_pressed = i == selected
		_buttons[i].disabled = not visited.has(i)
	_update_markers()
	$Zoom/Scale.text = "%d×" % int(zoom)
	$Zoom/Minus.disabled = not known or zoom <= 1
	$Zoom/Plus.disabled = not known or zoom >= 4

func change_zoom(direction: int) -> void:
	var old := zoom
	zoom = clampf(zoom * (2 if direction > 0 else .5), 1, 4)
	var center := Vector2(scroll.scroll_horizontal,scroll.scroll_vertical) + scroll.size * .5
	plan.custom_minimum_size = Vector2(510,566) * zoom
	await get_tree().process_frame
	scroll.scroll_horizontal = roundi(center.x * zoom/old - scroll.size.x * .5)
	scroll.scroll_vertical = roundi(center.y * zoom/old - scroll.size.y * .5)
	select_floor(selected)

func _pan_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_panning = event.pressed and zoom > 1
	elif event is InputEventMouseMotion and _panning:
		scroll.scroll_horizontal -= roundi(event.relative.x)
		scroll.scroll_vertical -= roundi(event.relative.y)
		scroll.accept_event()

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	if get_viewport() is SubViewport and get_viewport().render_target_update_mode == SubViewport.UPDATE_DISABLED: return
	_elapsed += delta
	if _elapsed < .1: return
	_elapsed = 0.0
	_update_markers()

func _update_markers() -> void:
	marker.hide()
	mate_marker.hide()
	if not visited.has(selected): return
	actor = get_tree().get_first_node_in_group("local_player") as GamePlayer
	if actor == null: return
	_place(marker, actor)
	for player in get_tree().get_nodes_in_group("network_players"):
		if player != actor and player is GamePlayer and not player.survival.dead:
			_place(mate_marker, player)
			break

func _place(pin: Polygon2D, player: GamePlayer) -> void:
	if level_for(player.global_position) != selected: return
	var data := atlas.floors[selected]
	# TextureRect preserves its 800:850 authored aspect ratio.
	var factor: float = minf(plan.size.x / data.sheet_size.x, plan.size.y / data.sheet_size.y)
	var offset := (plan.size - data.sheet_size * factor) * .5
	pin.position = offset + data.map_point(player.global_position) * factor
	pin.rotation = -player.rotation.y
	pin.show()
