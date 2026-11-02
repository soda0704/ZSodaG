extends Control
## Screen effect belongs to the local player's active camera, below the HUD.
@export var effect_enabled := true:
	set(value):
		effect_enabled = value
		if is_node_ready(): _update_visibility()

@onready var player: GamePlayer = get_parent().get_parent()
@onready var camera: Camera3D = player.get_node("Head/Camera3D")
@onready var effect_material: ShaderMaterial = $Effect.material
var motion_blur_enabled := false
var motion_blur_strength := 0.35
var _previous_pose := Transform3D.IDENTITY
var _history_valid := false
var _cooldown := 0.12
var _direction := Vector2.ZERO
var _radial := 0.0
var _lens_amount := 1.0
var _rim_input := Vector2.ZERO
var _rim_target := Vector2.ZERO
var _rim_offset := Vector2.ZERO

func _ready() -> void:
	get_viewport().size_changed.connect(_sync_resolution)
	_sync_resolution()
	_update_visibility()
	var quality := get_node("/root/GameMenu/GraphicsQuality")
	quality.camera_effects_changed.connect(_apply_motion_settings)
	_apply_motion_settings(bool(quality.values.get("MotionBlur", false)), float(quality.values.get("MotionBlurStrength", 35)) / 100.0)

func _sync_resolution() -> void:
	var size:=Vector2(get_viewport().get_texture().get_size()).max(Vector2.ONE)
	$Effect.material.set_shader_parameter("resolution",size)

func _apply_motion_settings(enabled: bool, strength: float) -> void:
	motion_blur_enabled = enabled
	motion_blur_strength = clampf(strength, 0.0, 1.0)
	reset_motion_history()

func reset_motion_history(reset_parallax: bool = true) -> void:
	if reset_parallax:
		_rim_input = Vector2.ZERO
		_rim_target = Vector2.ZERO
		_rim_offset = Vector2.ZERO
		if is_node_ready(): effect_material.set_shader_parameter("vignette_offset", Vector2.ZERO)
	_history_valid = false
	_cooldown = 0.12
	_direction = Vector2.ZERO
	_radial = 0.0
	if is_node_ready():
		effect_material.set_shader_parameter("motion_blur_enabled", false)
		effect_material.set_shader_parameter("blur_direction", Vector2.ZERO)
		effect_material.set_shader_parameter("radial_blur", 0.0)

func _input(event: InputEvent) -> void:
	# Captured mouse stays at the screen centre, so use its relative movement.
	# Observing input here never consumes it or changes the player's look input.
	if event is InputEventMouseMotion and visible and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_rim_input += event.relative

func _update_corner_parallax(delta: float, active: bool) -> void:
	if not active or delta <= 0.0 or delta > 0.15:
		_rim_input = Vector2.ZERO
		_rim_target = Vector2.ZERO
		_rim_offset = Vector2.ZERO
	else:
		var height := maxf(get_viewport().get_visible_rect().size.y, 1.0)
		_rim_target = (_rim_target + _rim_input / height * 0.045).limit_length(0.012)
		_rim_target *= exp(-6.0 * delta)
		_rim_offset = _rim_offset.lerp(_rim_target, 1.0 - exp(-14.0 * delta))
		_rim_input = Vector2.ZERO
	effect_material.set_shader_parameter("vignette_offset", _rim_offset)

func _process(delta: float) -> void:
	_update_visibility()
	# The journal's projected page hit tests use the undistorted camera projection.
	var reading := player._is_journal_open()
	var look_active: bool = visible and not reading and not player.is_bunk_busy() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not get_node("/root/GameMenu").is_menu_open()
	_update_corner_parallax(delta, look_active)
	_lens_amount = move_toward(_lens_amount, 0.0 if reading else 1.0, delta * 8.0)
	effect_material.set_shader_parameter("lens_amount", _lens_amount)
	if not look_active or not motion_blur_enabled or motion_blur_strength <= 0.0 or delta <= 0.0 or delta > 0.15:
		reset_motion_history(false)
		return
	var pose := camera.get_global_transform_interpolated()
	if not _history_valid:
		_previous_pose = pose
		_history_valid = true
	var displacement := pose.origin - _previous_pose.origin
	var angle := pose.basis.get_rotation_quaternion().angle_to(_previous_pose.basis.get_rotation_quaternion())
	if displacement.length() > 2.0 or angle > deg_to_rad(45.0):
		reset_motion_history()
		return
	_cooldown = maxf(0.0, _cooldown - delta)
	if _cooldown > 0.0:
		_previous_pose = pose
		return
	# Approximate shutter flow at 8 m, using the render-interpolated camera pose.
	# No previous-frame image is accumulated, so blur cannot leave ghost trails.
	var previous_point := _previous_pose.origin - _previous_pose.basis.z * 8.0
	var local_point := pose.affine_inverse() * previous_point
	var clip := camera.get_camera_projection() * Vector4(local_point.x, local_point.y, local_point.z, 1.0)
	var flow := Vector2.ZERO
	if clip.w > 0.001:
		flow = Vector2(clip.x, -clip.y) / clip.w * 0.5
	var shutter_ratio := (1.0 / 60.0) / delta * motion_blur_strength
	var target_direction := (flow * shutter_ratio).limit_length(0.012)
	var target_radial := clampf(-pose.basis.z.dot(displacement) / 8.0 * shutter_ratio, -0.012, 0.012)
	var smoothing := 1.0 - exp(-18.0 * delta)
	_direction = _direction.lerp(target_direction, smoothing)
	_radial = lerpf(_radial, target_radial, smoothing)
	_previous_pose = pose
	effect_material.set_shader_parameter("blur_direction", _direction)
	effect_material.set_shader_parameter("radial_blur", _radial)
	effect_material.set_shader_parameter("motion_blur_enabled", _direction.length() + absf(_radial) > 0.00002)

func _update_visibility() -> void:
	visible = effect_enabled and player.is_local_player() and camera.is_current()
