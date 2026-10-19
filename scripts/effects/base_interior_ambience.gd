extends AudioStreamPlayer
## One local, non-positional bed for every floor, faded by base occupancy.
# The supplied recording peaks near -22 dBFS; this gain leaves about 6 dB of headroom.
@export var ambience_volume_db := 16.0
@export_range(0.1, 10.0) var fade_seconds := 1.5
@export var base_regions: Array[AABB] = []
@export var acoustics_path := NodePath("../BaseAmbience")
@onready var _base_root: Node3D = get_parent() as Node3D
@onready var _acoustics: ExteriorAcoustics = get_node_or_null(acoustics_path) as ExteriorAcoustics
var _blend := 0.0
var _started := false

func contains_point(point: Vector3) -> bool:
	var local := _base_root.to_local(point)
	for region in base_regions:
		if region.has_point(local):
			return true
	return false

func mix_presence(delta: float, inside: bool) -> void:
	_blend = move_toward(_blend, 1.0 if inside else 0.0, delta / maxf(fade_seconds, 0.01))
	volume_db = linear_to_db(maxf(db_to_linear(ambience_volume_db) * smoothstep(0.0, 1.0, _blend), 0.00001))
	if _blend > 0.0 and not _started:
		play()
		_started = true
	# Resume the same recording after a complete fade, rather than restarting it.
	stream_paused = is_zero_approx(_blend)

func _process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("local_player") as GamePlayer
	var inside := false
	if is_instance_valid(player) and player.is_inside_tree():
		var point := player.camera.global_position
		inside = contains_point(point) and (_base_root.to_local(point).y < -8.0 or (_acoustics != null and _acoustics.is_inside))
	mix_presence(delta, inside)
