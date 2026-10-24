class_name JournalMapFloor
extends Resource
## Offline-baked floor plan, editable through the Inspector.
@export var title := ""
@export var level_label := ""
@export var elevation := 0.0
@export var scene_root: NodePath
@export var plan: Texture2D
@export var world_rect: Rect2
@export var drawing_rect := Rect2(40, 65, 720, 670)
@export var sheet_size := Vector2(800, 850)

func map_point(world: Vector3) -> Vector2:
	return drawing_rect.position + (Vector2(world.x, world.z) - world_rect.position) / world_rect.size * drawing_rect.size
