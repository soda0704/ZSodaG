extends RefCounted
## Shared accumulation profile for terrain authoring and movement through deep snow.

const DEPTH_FILE := "res://assets/environments/snow/interactive_snow_depth.res"
const DEPTH_ORIGIN := Vector2i(-512, -768)
const PROFILE_RANGE := 3.0
const DEPTH_RANGE := 1.0
static var _depth_image: Image
var _wind := FastNoiseLite.new()
var _broad := FastNoiseLite.new()
var _small := FastNoiseLite.new()

func _init() -> void:
	_wind.seed = 41981
	_wind.frequency = 0.044
	_broad.seed = 81731
	_broad.frequency = 0.016
	_small.seed = 65323
	_small.frequency = 0.135

func thickness(point: Vector2) -> float:
	var wind_space := point.rotated(-atan2(0.4, 1.0))
	var swell := _broad.get_noise_2d(point.x, point.y)
	var warped_crosswind := wind_space.y + 11.0 * swell
	var crest := _wind.get_noise_2d(wind_space.x * 0.23, warped_crosswind)
	var cluster := smoothstep(-0.43, 0.48, _broad.get_noise_2d(point.x + 350.0, point.y - 161.0))
	var windward := smoothstep(-0.34, 0.60, crest)
	var large_drift := windward * (0.72 + 2.24 * cluster)
	var small_crest := _small.get_noise_2d(wind_space.x * 0.46 + 13.0, warped_crosswind)
	var pocket := smoothstep(-0.25, 0.66, small_crest)
	# Small deposits fill the gaps between broader crests and fade underneath their peaks.
	var small_drift := pocket * (0.26 + 0.48 * (1.0 - windward))
	return minf(1.0, (large_drift + small_drift * (1.0 - windward * 0.65)) / PROFILE_RANGE)

static func route_x_at(z: float) -> float:
	var t := clampf((z - 3.0) / 92.0, 0.0, 1.0)
	return lerpf(-38.8, -94.0, t) - sin(t * TAU) * 7.5 + sin(t * TAU * 2.0) * 2.1

func depth_for_walking(point: Vector2) -> float:
	if _depth_image == null:
		var texture := load(DEPTH_FILE) as Texture2D
		if texture == null:
			return 0.0
		_depth_image = texture.get_image()
	var local := point - Vector2(DEPTH_ORIGIN)
	var grid := Vector2i(local.floor())
	var area := Rect2i(Vector2i.ZERO, _depth_image.get_size() - Vector2i.ONE)
	if not area.has_point(grid):
		return 0.0
	var fraction := local - Vector2(grid)
	var upper := lerpf(_depth_image.get_pixelv(grid).r, _depth_image.get_pixelv(grid + Vector2i.RIGHT).r, fraction.x)
	var lower := lerpf(_depth_image.get_pixelv(grid + Vector2i.DOWN).r, _depth_image.get_pixelv(grid + Vector2i.ONE).r, fraction.x)
	return lerpf(upper, lower, fraction.y) * DEPTH_RANGE
