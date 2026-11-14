extends Control
## The same safe rectangle used by the in-game HUD, at the actual screen edges.
const LAYOUT = preload("res://scripts/ui/hud_layout.gd")
const FONT = preload("res://assets/fonts/hud/body.tres")
var margin_percent := 0.0

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	var safe := LAYOUT.safe_rect(size, margin_percent).grow(-8)
	var ink := Color("efefe8")
	for corner in [Vector2.ZERO, Vector2(1, 0), Vector2(0, 1), Vector2.ONE]:
		var point: Vector2 = safe.position + safe.size * corner
		var direction: Vector2 = Vector2.ONE - corner * 2
		draw_line(point, point + Vector2(direction.x * 24, 0), ink, 2, true)
		draw_line(point, point + Vector2(0, direction.y * 24), ink, 2, true)
	draw_string(FONT, safe.position + Vector2(120, 68), "ТЕКУЩАЯ ЗАДАЧА", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("c3cbc9"))
	draw_string(FONT, Vector2(safe.position.x + 24, safe.end.y - 110), "100", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, ink)
	draw_line(Vector2(safe.position.x + 80, safe.end.y - 118), Vector2(safe.position.x + 180, safe.end.y - 118), ink, 3)
	draw_string(FONT, Vector2(safe.end.x - 75, safe.end.y - 110), "100%", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, ink)
	draw_string(FONT, Vector2(size.x * .5 - 35, safe.position.y + 68), "N   NE", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, ink)
	draw_circle(size * .5, 2, ink)
