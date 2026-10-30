extends Node3D
## Native clips own pose/timing; authority still owns sleep, recovery and day changes.
@export var progress := 0.0
@export var alignment := 0.0
@export var eye_openness := 1.0
@onready var player: GamePlayer = get_parent()
@onready var animation: AnimationPlayer = $AnimationPlayer
@onready var camera_pose: Node3D = $CameraPose
var active := false
var waking := false
var pose_time := 0.0
var _source_head := Transform3D.IDENTITY
var _source_body := Transform3D.IDENTITY
var _camera_start_offset := Vector3.ZERO
var _from_pose := 1.25
var _from_openness := 0.0

func _ready() -> void:
	animation.animation_finished.connect(_finished)

func begin(sleeping: bool, source_head: Transform3D, source_body: Transform3D) -> void:
	_from_pose = pose_time if active else 1.25
	_from_openness=float(player.get_node("PlayerUI/SleepEyelids/Cover").material.get_shader_parameter("openness"))
	_source_head=source_head;_source_body=source_body
	active=true;waking=not sleeping
	animation.play(&"lie_down" if sleeping else &"get_up")
	animation.advance(0)
	_camera_start_offset=_source_head.origin-(_source_body*camera_pose.transform).origin
	# The camera keeps its preceding world pose even though the collision root moves.
	_apply_pose()

func _process(_delta: float) -> void:
	if not active: return
	if player.survival.dead:
		cancel();return
	_apply_pose()

func _apply_pose() -> void:
	progress=clampf(progress,0.0,1.0);alignment=clampf(alignment,0.0,1.0);eye_openness=clampf(eye_openness,0.0,1.0)
	pose_time=lerpf(_from_pose,2.5 if _from_pose>=1.24 else 0.0,progress) if waking else progress*1.25
	var body_pose:=_source_body.interpolate_with(player.global_transform,alignment)
	# Keep the original body motion and view rotation. Only camera position
	# follows the head marker in body space instead of the relocated root.
	var target:=player.global_transform*camera_pose.transform
	var from_angles:=_source_head.basis.get_euler();var to_angles:=target.basis.get_euler()
	var yaw_weight:=smoothstep(.58,1.0,progress) if waking else smoothstep(0.0,.30,progress)
	var angles:=Vector3(lerp_angle(from_angles.x,to_angles.x,alignment),lerp_angle(from_angles.y,to_angles.y,yaw_weight),lerp_angle(from_angles.z,to_angles.z,alignment))
	var camera_origin:=(body_pose*camera_pose.transform).origin+_camera_start_offset*(1.0-alignment)
	if waking and _from_pose<1.24:
		camera_origin=_source_head.origin.lerp(target.origin,alignment)
	player.head.global_transform=Transform3D(Basis.from_euler(angles),camera_origin)
	player.body_animator.global_transform=body_pose
	if player.is_local_player():
		var openness:=maxf(eye_openness,_from_openness*(1.0-smoothstep(0.0,.6,progress))) if waking else eye_openness
		player.get_node("PlayerUI/SleepEyelids").set_openness(openness)

func _finished(_clip: StringName) -> void:
	_apply_pose()
	if not waking: return
	active=false;waking=false
	player.body_animator.transform=Transform3D.IDENTITY
	player.head.position=Vector3(0,player.standing_head_height,0)
	player.head.rotation=Vector3.ZERO
	player.camera.reset_motion()
	player._refresh_equipment_visuals()
	player.reset_physics_interpolation()

func cancel() -> void:
	animation.stop();active=false;waking=false;pose_time=0
	player.body_animator.transform=Transform3D.IDENTITY
	player.head.position=Vector3(0,player.standing_head_height,0);player.head.rotation=Vector3.ZERO
	if player.is_local_player(): player.get_node("PlayerUI/SleepEyelids").set_openness(1.0)
