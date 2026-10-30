extends AudioStreamPlayer3D
## Audio is the clock for an offline-authored native Animation, not random frame noise.
@export_node_path("Light3D") var lamp_path: NodePath
@export_node_path("CSGBox3D") var fixture_path: NodePath
@export_node_path("BasePowerLightingController") var power_controller_path: NodePath
@export_range(-40.0, 0.0) var running_volume_db := -12.0
@export_range(0.02, 1.0) var fade_seconds := 0.08
@export_range(0.0, 5.0) var emission_energy := 1.3
@export_range(0.0, 1.0) var intensity := 0.0:
	set(value):
		intensity = clampf(value, 0.0, 1.0)
		if is_instance_valid(_lighting) and is_instance_valid(_lamp):
			_lighting.set_lamp_modulation(_lamp, intensity)
		if _material != null:
			_material.emission_energy_multiplier = emission_energy * intensity
var _lighting: WorldLighting
var _lamp: Light3D
var _material: StandardMaterial3D
var _power: BasePowerLightingController
var _powered := false
var _gain := 0.0
@onready var _animation: AnimationPlayer = $AnimationPlayer

func _ready() -> void:
	volume_db = -80.0
	_animation.play(&"fault")
	_animation.pause()
	_bind.call_deferred()

func _bind() -> void:
	_lamp = get_node_or_null(lamp_path) as Light3D
	_lighting = _lamp.get_parent().get_parent() as WorldLighting if _lamp != null else null
	var fixture := get_node_or_null(fixture_path) as CSGBox3D
	if fixture != null and fixture.material is StandardMaterial3D:
		# Never animate the shared art-library material or another fixture instance.
		_material = fixture.material.duplicate() as StandardMaterial3D
		fixture.material = _material
	_power = get_node_or_null(power_controller_path) as BasePowerLightingController
	if _power != null:
		_power.lighting_state_changed.connect(_set_powered)
	_set_powered(_power != null and _power.is_standard_powered)

func _set_powered(value: bool) -> void:
	_powered = value
	if not value:
		intensity = 0.0
	elif not playing:
		play()
		_animation.seek(0.0, true)

func _process(delta: float) -> void:
	_gain = move_toward(_gain, 1.0 if _powered else 0.0, delta / fade_seconds)
	volume_db = running_volume_db + linear_to_db(maxf(_gain, 0.00001))
	if not _powered:
		if is_zero_approx(_gain) and playing: stop()
		return
	if not playing: return
	# Position follows the audible output, including loop wrap and stream pauses.
	var clock := get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()
	_animation.seek(fposmod(maxf(0.0, clock), stream.get_length()), true)

func _exit_tree() -> void:
	if is_instance_valid(_lighting) and is_instance_valid(_lamp):
		_lighting.set_lamp_modulation(_lamp, 1.0)
