extends Control
## The same safe rectangle used by the in-game HUD, at the actual screen edges.
const LAYOUT = preload("res://scripts/ui/hud_layout.gd")
const FONT = preload("res://assets/fonts/hud/body.tres")
var margin_percent := 0.0

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	var safe := LAYOUT.safe_rect(size, margin_percent)
	var hud_scale := LAYOUT.scale_for(get_viewport())
	var extent := safe.size / hud_scale
	var ink := LAYOUT.CAMERA_INK
	draw_set_transform(safe.position, 0.0, Vector2.ONE * hud_scale)
	LAYOUT.draw_camera_corners(self, extent)
	var inset := LAYOUT.content_inset(extent)
	draw_circle(LAYOUT.RECORD_DOT + inset, 7.0, LAYOUT.RECORD_RED, true, -1.0, true)
	draw_string(FONT, LAYOUT.RECORD_LABEL + inset, "ЗАПИСЬ", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, ink)
	draw_string(FONT, LAYOUT.RECORD_CLOCK + inset, "00:00:00", HORIZONTAL_ALIGNMENT_LEFT, -1, 27, ink)
	var baseline := extent.y - LAYOUT.PRIMARY_STATUS_INSET - 16.0 - inset.y
	var health_font_size := roundi(34 * LAYOUT.HEALTH_SCALE)
	var health_x := 104 + 22 * LAYOUT.HEALTH_SCALE + inset.x
	draw_string(FONT, Vector2(health_x, baseline), "100", HORIZONTAL_ALIGNMENT_LEFT, -1, health_font_size, ink)
	var bar_x := health_x + 18 * LAYOUT.HEALTH_SCALE + FONT.get_string_size("100", HORIZONTAL_ALIGNMENT_LEFT, -1, health_font_size).x
	var bar_y := baseline - 10 * LAYOUT.HEALTH_SCALE
	draw_line(Vector2(bar_x, bar_y), Vector2(bar_x + 144 * LAYOUT.HEALTH_SCALE, bar_y), ink, 3 * LAYOUT.HEALTH_SCALE, true)
	draw_string(FONT, Vector2(extent.x - 147 - inset.x, baseline), "100%", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, ink)
	draw_string(FONT, Vector2(extent.x * 0.5 - 48, 47 + inset.y), "N     NE", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, ink)
	LAYOUT.draw_reticle(self, extent * 0.5)
