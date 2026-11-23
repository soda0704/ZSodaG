extends RefCounted
## World-space contact masks. Each tile is allocated only when a foot reaches it.

const TILE_METRES := 16.0
const SnowDriftProfile := preload("res://scripts/effects/snow_drift_profile.gd")
const RESOLUTION := 192
const TILE_COUNT := 12
const TRACE_LIFETIME := 42
const EMPTY_TILE := Vector2i(62500, 62500)
# Contact width follows the player. The height map determines how deep the groove looks.
const FLOOR_RADIUS := 0.60
const WALL_RADIUS := 1.18
const BANK_START := lerpf(FLOOR_RADIUS, WALL_RADIUS, 0.42)
const STAMP_RADIUS := 1.46
const STAMP_RADIUS_SQUARED := STAMP_RADIUS * STAMP_RADIUS
const PIXEL_SIZE := TILE_METRES / RESOLUTION

var _keys: Array[Vector2i] = []
var _last_touch: Array[int] = []
var _last_activity: Array[float] = []
var _origins := PackedVector2Array()
var _order := 0
var _dirty := false
var _atlas := Image.create_empty(RESOLUTION * 4, RESOLUTION * 3, false, Image.FORMAT_RGBA8)
var texture := ImageTexture.create_from_image(_atlas)
var _last_clock_tick := -1
var _last_upload := -1.0
var _stamp_time := 0
var _stamp_clock := 0.0

func _init() -> void:
	_origins.resize(TILE_COUNT)
	_origins.fill(Vector2(1000000.0, 1000000.0))

func push_snow(from: Vector3, to: Vector3, timestamp: float, width: float = 0.58) -> void:
	_stamp_clock = timestamp
	_stamp_time = floori(timestamp) & 65535
	var start := Vector2(from.x, from.z)
	var finish := Vector2(to.x, to.z)
	var direction := (finish - start).normalized()
	for sample in range(1, ceili(start.distance_to(finish) / 0.16) + 1):
		var point := start.move_toward(finish, sample * 0.16)
		if packed_at(point) < 0.45:
			_stamp(point, direction, width)

static func packed_at(point: Vector2) -> float:
	var x := SnowDriftProfile.route_x_at(point.y)
	var ends := smoothstep(1.0, 3.0, point.y) * (1.0 - smoothstep(94.0, 98.0, point.y))
	return ends * (1.0 - smoothstep(0.66, 1.85, absf(point.x - x) * 0.72))

func _tile(key: Vector2i) -> int:
	var slot := _keys.find(key)
	if slot < 0:
		slot = _keys.find(EMPTY_TILE)
		if slot < 0 and _keys.size() == TILE_COUNT:
			slot = _last_touch.find(_last_touch.min())
		if slot >= 0:
			_atlas.fill_rect(Rect2i(_atlas_origin(slot), Vector2i.ONE * RESOLUTION), Color.TRANSPARENT)
			_keys[slot] = key
		else:
			slot = _keys.size()
			_keys.append(key)
			_last_touch.append(0)
			_last_activity.append(0.0)
		_origins[slot] = Vector2(key) * TILE_METRES
	_order += 1
	_last_touch[slot] = _order
	_last_activity[slot] = _stamp_clock
	return slot

func _atlas_origin(slot: int) -> Vector2i:
	return Vector2i(slot % 4, floori(slot / 4.0)) * RESOLUTION

func _stamp(point: Vector2, direction: Vector2, width: float) -> void:
	var side := direction.orthogonal()
	var radius := STAMP_RADIUS * width
	var min_tile := Vector2i(((point - Vector2.ONE * radius) / TILE_METRES).floor())
	var max_tile := Vector2i(((point + Vector2.ONE * radius) / TILE_METRES).floor())
	var radius_pixels := radius / PIXEL_SIZE
	var low := float(_stamp_time & 255) / 255.0
	var high := float(_stamp_time >> 8) / 255.0
	for tile_y in range(min_tile.y, max_tile.y + 1):
		for tile_x in range(min_tile.x, max_tile.x + 1):
			var key := Vector2i(tile_x, tile_y)
			var slot := _tile(key)
			var local := (point - _origins[slot]) / PIXEL_SIZE
			var atlas_origin := _atlas_origin(slot)
			for y in range(maxi(0, floori(local.y - radius_pixels)), mini(RESOLUTION, ceili(local.y + radius_pixels))):
				for x in range(maxi(0, floori(local.x - radius_pixels)), mini(RESOLUTION, ceili(local.x + radius_pixels))):
					var offset := (Vector2(x + 0.5, y + 0.5) - local) * PIXEL_SIZE
					var front := 1.0 - smoothstep(-0.08, 0.06, offset.dot(direction))
					if front <= 0.0:
						continue
					offset /= width
					var distance_squared := offset.length_squared()
					if distance_squared >= STAMP_RADIUS_SQUARED:
						continue
					var distance := sqrt(distance_squared)
					var world := point + offset * width
					var loose_edge := sin(world.x * 15.0 + world.y * 21.0) * 0.026
					var lateral := absf(offset.dot(side)) / maxf(distance, 0.001)
					var groove := 1.0 - smoothstep(FLOOR_RADIUS, WALL_RADIUS + loose_edge, distance)
					var bank := smoothstep(BANK_START, WALL_RADIUS + loose_edge, distance)
					bank *= 1.0 - smoothstep(WALL_RADIUS, STAMP_RADIUS, distance)
					bank *= lateral
					groove *= front
					bank *= front
					if groove + bank < 0.005:
						continue
					var pixel := atlas_origin + Vector2i(x, y)
					var previous := _atlas.get_pixelv(pixel)
					var previous_tick := roundi(previous.b * 255.0) + 256 * roundi(previous.a * 255.0)
					var age := (_stamp_time - previous_tick) & 65535
					var remaining := 1.0 - smoothstep(26.0, float(TRACE_LIFETIME), float(age))
					_atlas.set_pixelv(pixel, Color(maxf(previous.r * remaining, groove), maxf(previous.g * remaining, bank), low, high))
	_dirty = true

func flush(material: Terrain3DMaterial, clock: float = 0.0) -> void:
	var tick := floori(clock * 4.0)
	var expired := false
	if tick != _last_clock_tick and not _keys.is_empty():
		material.set_shader_param("snow_clock", fposmod(clock, 65536.0))
		_last_clock_tick = tick
		for slot in _keys.size():
			if _keys[slot] != EMPTY_TILE and clock - _last_activity[slot] >= TRACE_LIFETIME:
				_keys[slot] = EMPTY_TILE
				_origins[slot] = Vector2(EMPTY_TILE) * TILE_METRES
				expired = true
	var upload := _dirty and (clock < _last_upload or clock - _last_upload >= 1.0 / 30.0)
	if upload:
		texture.update(_atlas)
		_last_upload = clock
	if upload or expired:
		var active_end := _keys.size()
		while active_end > 0 and _keys[active_end - 1] == EMPTY_TILE:
			active_end -= 1
		material.set_shader_param("snow_tile_origins", _origins)
		material.set_shader_param("snow_tile_count", active_end)
	if upload:
		_dirty = false
