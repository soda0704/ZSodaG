extends RefCounted
## Keep the reference composition, with readable text in smaller windows.
const CAMERA_INK := Color(0.97, 0.97, 0.94, 0.94)
const RECORD_RED := Color("db524e")
const RECORD_DOT := Vector2(90, 86)
const RECORD_LABEL := Vector2(108, 96)
const RECORD_CLOCK := Vector2(82, 128)
const PRIMARY_STATUS_INSET := 126.0
const HEALTH_SCALE := 1.23
const CENTER_PULL := 0.14
const CORNER_ARM := 28.0

static func centered(extent: Vector2, point: Vector2) -> Vector2:
	return point.lerp(extent * 0.5, CENTER_PULL)

static func group_scale(extent: Vector2) -> float:
	return clampf(extent.x / 2850.0, 0.54, 0.90)

static func content_inset(extent: Vector2) -> Vector2:
	return Vector2(clampf(extent.x * 0.026, 40.0, 84.0), clampf(extent.y * 0.025, 25.0, 48.0))

static func draw_reticle(canvas: Control, center: Vector2) -> void:
	canvas.draw_circle(center, 2.6, Color(0.04, 0.05, 0.06, 0.62), true, -1.0, true)
	canvas.draw_circle(center, 1.7, Color(CAMERA_INK, 0.78), true, -1.0, true)

static func camera_corner_anchor(extent: Vector2, direction: Vector2) -> Vector2:
	var inset := Vector2(44.0, 44.0) + content_inset(extent)
	var edge := extent * (Vector2.ONE - direction) * 0.5 + direction * inset
	return centered(extent, edge) - direction * Vector2(34.0, 34.0)


static func draw_camera_corners(canvas: Control, extent: Vector2) -> void:
	for direction: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var at := camera_corner_anchor(extent, direction)
		for axis: Vector2 in [Vector2(direction.x, 0), Vector2(0, direction.y)]:
			canvas.draw_line(at + Vector2.DOWN, at + axis * CORNER_ARM + Vector2.DOWN, Color(0, 0, 0, 0.65), 2.0, true)
			canvas.draw_line(at, at + axis * CORNER_ARM, Color(CAMERA_INK, 0.78), 1.5, true)

static func scale_for(viewport: Viewport) -> float:
	var logical_size := viewport.get_visible_rect().size
	var stretch := viewport.get_stretch_transform().get_scale().abs()
	var pixel_size := logical_size * stretch
	var reference := minf(pixel_size.x / 2688.0, pixel_size.y / 1512.0)
	# The compact canvas leaves room for all three bottom groups and the objective.
	var readable := minf(0.60, minf(pixel_size.x / 1600.0, pixel_size.y / 1000.0))
	return maxf(maxf(reference, readable) / maxf(minf(stretch.x, stretch.y), 0.001), 0.01)

static func safe_rect(viewport_size: Vector2, margin_percent: float) -> Rect2:
	var inset := viewport_size * clampf(margin_percent, 0.0, 10.0) / 100.0
	return Rect2(inset, viewport_size - inset * 2.0)
