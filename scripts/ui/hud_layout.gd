extends RefCounted
## Keep the reference composition, with readable text in smaller windows.
static func scale_for(viewport: Viewport) -> float:
	var logical_size := viewport.get_visible_rect().size
	var stretch := viewport.get_stretch_transform().get_scale().abs()
	var pixel_size := logical_size * stretch
	var reference := minf(pixel_size.x / 2560.0, pixel_size.y / 1440.0)
	# The compact canvas leaves room for all three bottom groups and the objective.
	var readable := minf(0.60, minf(pixel_size.x / 1600.0, pixel_size.y / 1000.0))
	return maxf(maxf(reference, readable) / maxf(minf(stretch.x, stretch.y), 0.001), 0.01)
