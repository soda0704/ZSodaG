extends SceneTree
## Bakes loose snow separately from the collision surface.

const TERRAIN_DIRECTORY := "res://assets/environments/snow/expanded_terrain/"
const WATER_LAYOUT := "res://assets/environments/snow/smooth_stream_layout.json"
const BASINS := [Vector4(-110, -105, 53, 40), Vector4(105, 95, 44, 24), Vector4(-215, 90, 29, 43)]
const WIND_STEP := Vector2i(7, 3)
const CROSSWIND_STEP := Vector2i(-3, 7)
const HELIPAD := Vector2(-125, 95)
const TOWER := Vector2(0, -180)
const SnowDriftProfile := preload("res://scripts/effects/snow_drift_profile.gd")

var _profile := SnowDriftProfile.new()
var _heights: Dictionary[Vector2i, Image] = {}
var _controls: Dictionary[Vector2i, PackedByteArray] = {}
var _stream: Array = []
var _region_size := 0

func _initialize() -> void:
	_bake.call_deferred()

func _bake() -> void:
	var layout: Variant = JSON.parse_string(FileAccess.get_file_as_string(WATER_LAYOUT))
	if not layout is Array or layout.size() < 2:
		push_error("Snow bake requires the stream layout.")
		quit(1)
		return
	_stream = layout
	for file in DirAccess.get_files_at(TERRAIN_DIRECTORY):
		if not file.ends_with(".res"):
			continue
		var region := load(TERRAIN_DIRECTORY + file) as Terrain3DRegion
		if region == null:
			push_error("Could not read terrain region: " + file)
			quit(1)
			return
		var location := Terrain3DUtil.filename_to_location(file)
		_region_size = region.get_region_size()
		_heights[location] = region.get_height_map()
		_controls[location] = region.get_control_map().get_data()
	if _heights.is_empty():
		quit(1)
		return
	var depth_map := Image.create_empty(2048, 1536, false, Image.FORMAT_R8)
	var bounds := Rect2i(SnowDriftProfile.DEPTH_ORIGIN, depth_map.get_size())
	var deepest := 0.0
	var deep_cells := 0
	for location in _heights:
		var height_map := _heights[location]
		var control := _controls[location]
		var origin := location * _region_size
		var area := bounds.intersection(Rect2i(origin, height_map.get_size()))
		for z in range(area.position.y, area.end.y):
			for x in range(area.position.x, area.end.x):
				var point := Vector2i(x, z)
				var local := point - origin
				var h := height_map.get_pixelv(local).r
				if not is_finite(h) or (control[(local.y * _region_size + local.x) * 4] & 4) != 0:
					continue
				var access := _clearance(Vector2(point))
				if access <= 0.001:
					continue
				var depth := _accumulation(point, h) * access
				depth_map.set_pixelv(point - bounds.position, Color(depth / SnowDriftProfile.DEPTH_RANGE, 0, 0))
				deepest = maxf(depth, deepest)
				deep_cells += int(depth >= 0.60)
		await process_frame
	var result := ResourceSaver.save(ImageTexture.create_from_image(depth_map), SnowDriftProfile.DEPTH_FILE, ResourceSaver.FLAG_COMPRESS)
	if result != OK:
		push_error("Could not save interactive snow depth: " + error_string(result))
	print("SNOW DEPTH: ", _heights.size(), " regions, max ", deepest, " m; ", deep_cells, " m² above 60 cm")
	quit(0 if result == OK else 1)

func _accumulation(point: Vector2i, ground: float) -> float:
	var p := Vector2(point)
	var grade := Vector2(
		_height_at(point + Vector2i.RIGHT, ground) - _height_at(point + Vector2i.LEFT, ground),
		_height_at(point + Vector2i.DOWN, ground) - _height_at(point + Vector2i.UP, ground)) * 0.5
	var adhesion := 1.0 - smoothstep(0.32, 0.93, grade.length())
	var upwind := _height_at(point - WIND_STEP, ground) - ground
	var downwind := _height_at(point + WIND_STEP, ground) - ground
	var across := (_height_at(point + CROSSWIND_STEP, ground) + _height_at(point - CROSSWIND_STEP, ground)) * 0.5 - ground
	var lee := smoothstep(0.18, 1.55, upwind)
	var hollow := smoothstep(0.04, 0.75, across * 0.65 + (upwind + downwind) * 0.175)
	var exposed := smoothstep(0.16, 1.15, -upwind) * (1.0 - hollow)
	var loose := _profile.thickness(p)
	var base := (0.24 + loose * 0.41) * lerpf(1.0, 0.62, exposed)
	var retained := (lee * 0.32 + hollow * 0.24) * (0.48 + loose)
	var wake := maxf(_wake(p, Vector2(44, 18), 52.0, 26.0) * 0.48,
		maxf(_wake(p, HELIPAD + Vector2(11, 5), 40.0, 15.0) * 0.34,
			_wake(p, TOWER + Vector2(5, 2), 27.0, 10.0) * 0.29))
	return minf(SnowDriftProfile.DEPTH_RANGE, (base + retained + wake) * adhesion)

func _wake(p: Vector2, source: Vector2, length: float, spread: float) -> float:
	var wind := Vector2(WIND_STEP).normalized()
	var local := p - source
	var along := local.dot(wind)
	var cross := absf(local.dot(wind.orthogonal()))
	return smoothstep(0.0, length * 0.25, along) * (1.0 - smoothstep(length * 0.42, length, along)) \
		* (1.0 - smoothstep(spread * 0.22, spread, cross))

func _height_at(point: Vector2i, fallback: float) -> float:
	var region := Vector2i(floori(float(point.x) / _region_size), floori(float(point.y) / _region_size))
	var image := _heights.get(region) as Image
	if image == null:
		return fallback
	var sample := image.get_pixelv(point - region * _region_size).r
	return sample if is_finite(sample) else fallback

func _clearance(p: Vector2) -> float:
	var apron := Vector2(maxf(absf(p.x + 2.0) - 43.0, 0.0), maxf(absf(p.y) - 30.0, 0.0))
	var weight := smoothstep(0.0, 8.0, apron.length())
	weight *= smoothstep(18.0, 29.0, p.distance_to(HELIPAD))
	weight *= smoothstep(8.0, 17.0, p.distance_to(TOWER))
	weight *= smoothstep(1.0, 1.65, ((p - Vector2(335.0, 0.0)) / Vector2(62.0, 100.0)).length())
	if p.y > -2.0 and p.y < 104.0:
		var path := 1.0 - smoothstep(1.25, 4.0, absf(p.x - SnowDriftProfile.route_x_at(p.y)) * 0.72)
		var ends := smoothstep(-2.0, 2.0, p.y) * (1.0 - smoothstep(97.0, 104.0, p.y))
		weight *= 1.0 - path * ends
	if Rect2(-300, -260, 520, 460).has_point(p):
		for basin: Vector4 in BASINS:
			var offset := (p - Vector2(basin.x, basin.y)) / Vector2(basin.z, basin.w)
			weight *= smoothstep(1.09, 1.42, offset.length())
		for index in _stream.size() - 1:
			var row: Array = _stream[index]
			var next: Array = _stream[index + 1]
			var start := Vector2(row[0], row[1])
			if absf(p.x - start.x) > 42.0 or absf(p.y - start.y) > 42.0:
				continue
			var end := Vector2(next[0], next[1])
			var distance := p.distance_to(Geometry2D.get_closest_point_to_segment(p, start, end))
			weight = minf(weight, smoothstep(8.0, 16.0, distance - maxf(row[3], next[3])))
	return weight
