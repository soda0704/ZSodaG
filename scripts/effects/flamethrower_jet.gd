extends Node3D
## Drives an authored VFX scene from weapon state and the nearest obstruction.
@onready var animation: AnimationPlayer = $AnimationPlayer
@onready var stream: AudioStreamPlayer3D = $Roar
@onready var impact: Node3D = $Impact
@onready var plume: Array[GPUParticles3D] = [$Core,$Flames,$Smoke,$Embers]
var active := false

func _ready() -> void:
	animation.animation_finished.connect(_animation_finished)

func set_jet(enabled: bool, origin: Vector3, direction: Vector3, reach: float, hit_surface: bool) -> void:
	if enabled:
		global_transform = Transform3D(Basis.looking_at(direction, Vector3.RIGHT if absf(direction.y)>.98 else Vector3.UP), origin)
		var end := origin+direction*maxf(reach,0.0)
		var plane := Vector4(direction.x,direction.y,direction.z,-direction.dot(end))
		for particles in plume: particles.set_instance_shader_parameter(&"stop_plane",plane)
		impact.position = Vector3(0,0,-maxf(reach-.025,0.0))
	$Impact/Glow.visible = enabled and hit_surface
	$Impact/Flames.emitting = enabled and hit_surface
	$Impact/Smoke.emitting = enabled and hit_surface
	if enabled == active: return
	active = enabled
	for particles in plume: particles.emitting=enabled
	if enabled:
		stream.play()
		animation.play(&"ignite")
	else:
		animation.play(&"extinguish")

func _animation_finished(clip: StringName) -> void:
	if clip==&"ignite" and active: animation.play(&"burn")
	elif clip==&"extinguish" and not active: stream.stop()
