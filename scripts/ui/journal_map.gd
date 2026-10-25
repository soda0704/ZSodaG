extends Control
signal loupe_requested(active: bool)
signal content_changed
@export var atlas: JournalAtlas
@onready var plan: TextureRect = $MapScroll/Plan
@onready var title: Label = $Title
@onready var status: Label = $Status
@onready var empty: Label = $Empty
@onready var marker: Polygon2D = $MapScroll/Plan/Player
@onready var mate_marker: Polygon2D = $MapScroll/Plan/Teammate
@onready var scroll: ScrollContainer = $MapScroll
@onready var loupe_button: Button = $LoupeButton
var selected := 0
var visited: Array = []
var _buttons: Array[Node] = []
var _elapsed := 0.0
var actor: GamePlayer

func get_plan_rect() -> Rect2:
	# Exclude the TextureRect's aspect-fit padding from the physical sheet.
	var box := scroll.get_global_rect()
	var sheet_size := atlas.floors[selected].sheet_size
	var drawn := sheet_size*minf(box.size.x/sheet_size.x,box.size.y/sheet_size.y)
	return Rect2(box.position+(box.size-drawn)*.5,drawn)

func _ready() -> void:
	_buttons = $Levels.get_children()
	for i in _buttons.size(): _buttons[i].pressed.connect(select_floor.bind(i))
	loupe_button.toggled.connect(func(active): loupe_requested.emit(active))
	visibility_changed.connect(_on_visibility_changed)
	select_floor(0)

func _on_visibility_changed() -> void:
	if not is_visible_in_tree(): return
	actor = get_tree().get_first_node_in_group("local_player") as GamePlayer
	if actor != null:
		var level := level_for(actor.global_position)
		if visited.has(level): select_floor(level)

func update_visited(next: Array) -> void:
	if visited == next: return
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
	loupe_button.disabled = not known
	content_changed.emit()

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	if not get_node("/root/QuestJournal").is_journal_open(): return
	_elapsed += delta
	if _elapsed < .1: return
	_elapsed = 0.0
	_update_markers()

func _update_markers() -> void:
	var previous := [marker.visible,marker.position,marker.rotation,mate_marker.visible,mate_marker.position,mate_marker.rotation]
	actor = get_tree().get_first_node_in_group("local_player") as GamePlayer
	var known := visited.has(selected)
	marker.visible = known and actor != null and level_for(actor.global_position) == selected
	if marker.visible: _place(marker, actor)
	var mate: GamePlayer
	if known:
		for player in get_tree().get_nodes_in_group("network_players"):
			if player != actor and player is GamePlayer and not player.survival.dead:
				mate = player
				break
	mate_marker.visible = mate != null and level_for(mate.global_position) == selected
	if mate_marker.visible: _place(mate_marker,mate)
	if previous != [marker.visible,marker.position,marker.rotation,mate_marker.visible,mate_marker.position,mate_marker.rotation]:
		content_changed.emit()

func _place(pin: Polygon2D, player: GamePlayer) -> void:
	if level_for(player.global_position) != selected: return
	var data := atlas.floors[selected]
	# TextureRect preserves its 800:850 authored aspect ratio.
	var factor: float = minf(plan.size.x / data.sheet_size.x, plan.size.y / data.sheet_size.y)
	var offset := (plan.size - data.sheet_size * factor) * .5
	pin.position = offset + data.map_point(player.global_position) * factor
	pin.rotation = -player.rotation.y
	pin.show()
