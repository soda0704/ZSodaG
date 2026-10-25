extends Node3D
## One pasted paper sheet. Native clips own page motion; no unfolding states.
signal content_requested(show_map: bool)
signal transition_finished
@onready var animation: AnimationPlayer = $AnimationPlayer
var busy := false
var displaying_map := false
var _target_map := false
var _world_phase := 0
var loupe_active := false
@export var sheet_width := .21
@export var sheet_height := .303
@export var atlas_size := Vector2(1400,986)
var _map_rect := Rect2(140,184,510,566)
var magnifier: Node3D
var _lens_material: ShaderMaterial
var _live_atlas := false

func _ready() -> void:
	animation.animation_finished.connect(_on_animation_finished)
	$LoupeAnimation.animation_finished.connect(func(clip):
		if clip == &"lower" and not loupe_active:
			$LoupeAim.hide()
			if is_instance_valid(magnifier): magnifier.hide())
	reset()

func bind_ink(texture: Texture2D, rect: Rect2) -> void:
	var material: ShaderMaterial = $MapSheet/Paper.material_override
	material.set_shader_parameter("ink_texture", texture)
	material.set_shader_parameter("source_rect", Vector4(rect.position.x,rect.position.y,rect.size.x,rect.size.y))
	material.set_shader_parameter("paper_source_rect", Vector4(rect.position.x,rect.position.y,rect.size.x,rect.size.y))
	_map_rect = Rect2(rect.position*atlas_size,rect.size*atlas_size)
	_live_atlas = true
	if _lens_material != null:
		_lens_material.set_shader_parameter("ink_texture",texture)
		_lens_material.set_shader_parameter("live_atlas",true)
	set_loupe_focus(_map_rect.get_center())

func configure_grip(pose: Transform3D) -> void:
	if pose != Transform3D.IDENTITY: $LoupeAim/Lift/RightGrip.transform = pose

func configure_magnifier(visual: Node3D, pose: Transform3D) -> void:
	magnifier = visual
	magnifier.transform = pose.affine_inverse()
	magnifier.hide()
	_lens_material = magnifier.get_node("Lens").material_override
	var paper: ShaderMaterial = $MapSheet/Paper.material_override
	_lens_material.set_shader_parameter("ink_texture",paper.get_shader_parameter("ink_texture"))
	_lens_material.set_shader_parameter("paper_texture",paper.get_shader_parameter("paper_texture"))
	_lens_material.set_shader_parameter("paper_rect",paper.get_shader_parameter("paper_rect"))
	_lens_material.set_shader_parameter("live_atlas",_live_atlas)
	var skeleton := magnifier.get_parent().get_parent().get_parent() as Skeleton3D
	if not skeleton.skeleton_updated.is_connected(_sync_lens_focus): skeleton.skeleton_updated.connect(_sync_lens_focus)

func _sync_lens_focus() -> void:
	if not loupe_active or not is_instance_valid(magnifier): return
	var camera := get_viewport().get_camera_3d()
	if camera == null: return
	var lens: MeshInstance3D = magnifier.get_node("Lens")
	var size: Vector2 = lens.mesh.size
	var center := _lens_sample(lens.global_position,camera.global_position)
	# Project the actual glass footprint onto the paper. A fixed UV window
	# changes the apparent zoom when the wrist tilts or approaches the camera.
	var right := _lens_sample(lens.to_global(Vector3(size.x*.5,0,0)),camera.global_position)
	var down := _lens_sample(lens.to_global(Vector3(0,-size.y*.5,0)),camera.global_position)
	_lens_material.set_shader_parameter("focus_atlas",center)
	_lens_material.set_shader_parameter("window_axis_x",(right-center)*2.0)
	_lens_material.set_shader_parameter("window_axis_y",(down-center)*2.0)

func _lens_sample(at: Vector3, eye: Vector3) -> Vector2:
	at = to_local(at)
	eye = to_local(eye)
	var ray := at-eye
	if absf(ray.z)>.00001: at = eye+ray*(($MapSheet.position.z-eye.z)/ray.z)
	var point := Vector2((at.x/sheet_width+1)*atlas_size.x*.5,(.5-at.y/sheet_height)*atlas_size.y)
	return point/atlas_size if _live_atlas else (point-_map_rect.position)/_map_rect.size

func bind_paper(texture: Texture2D, rect: Vector4) -> void:
	for mesh in [$MapSheet/Paper,$TurnPivot/Page]:
		mesh.material_override.set_shader_parameter("paper_texture",texture)
		mesh.material_override.set_shader_parameter("paper_rect",rect)
	if _lens_material != null:
		_lens_material.set_shader_parameter("paper_texture",texture)
		_lens_material.set_shader_parameter("paper_rect",rect)

func set_loupe(enabled: bool) -> void:
	if enabled == loupe_active: return
	loupe_active = enabled
	$LoupeAim.show()
	if is_instance_valid(magnifier): magnifier.show()
	$LoupeAnimation.play("raise" if enabled else "lower")

func set_loupe_focus(point: Vector2) -> void:
	point = point.clamp(_map_rect.position+Vector2(40,40),_map_rect.end-Vector2(40,40))
	$LoupeAim.position = Vector3((point.x/(atlas_size.x*.5)-1.0)*sheet_width,(.5-point.y/atlas_size.y)*sheet_height,0)

func aim_loupe(origin: Vector3, direction: Vector3) -> void:
	var inverse := global_transform.affine_inverse()
	var a := inverse*origin
	var b := inverse.basis*direction
	if absf(b.z)<.00001: return
	var hit: Vector3 = a+b*(($LoupeAim/Lift.position.z-a.z)/b.z)
	set_loupe_focus(Vector2((hit.x/sheet_width+1)*atlas_size.x*.5,(.5-hit.y/sheet_height)*atlas_size.y))

func bind_turn_textures(previous: Texture2D, next: Texture2D, show_map: bool) -> void:
	var material: ShaderMaterial = $TurnPivot/Page.material_override
	material.set_shader_parameter("ink_texture", previous if show_map else next)
	# The UI quads include the cover margin. Crop to the native paper bounds.
	material.set_shader_parameter("source_rect", Vector4(.0357143,.0412541,.4428571,.9174918))
	material.set_shader_parameter("back_ink_texture", next if show_map else previous)
	material.set_shader_parameter("back_source_rect", Vector4(.5214286,.0412541,.4428571,.9174918))
	material.set_shader_parameter("printed_back", true)

func transition_to(show_map: bool) -> void:
	if busy or show_map == displaying_map: return
	set_loupe(false)
	busy = true
	_target_map = show_map
	# The turning leaf retains the old spread while the new page is revealed.
	content_requested.emit(show_map)
	animation.play("page_to_map" if show_map else "page_to_notes")
	# Apply the first pose before replacing the underlying atlas this frame.
	animation.advance(0)

func _on_animation_finished(clip: StringName) -> void:
	if not busy: return
	if clip not in [&"page_to_map", &"page_to_notes"]: return
	displaying_map = _target_map
	busy = false
	$MapSheet.visible = displaying_map
	$TurnPivot.hide()
	transition_finished.emit()

func reset() -> void:
	busy = false
	displaying_map = false
	_target_map = false
	animation.play("RESET")
	animation.advance(0)
	animation.stop()
	loupe_active = false
	$LoupeAnimation.stop()
	$LoupeAim.hide()
	if is_instance_valid(magnifier): magnifier.hide()

func snap_to_map() -> void:
	busy = false
	displaying_map = true
	_target_map = true
	animation.stop()
	$TurnPivot.hide()
	$MapSheet.show()

func return_to_notes() -> void:
	if not busy:
		transition_to(false)
		return
	var at := animation.current_animation_position
	var length := animation.current_animation_length
	_target_map = false
	content_requested.emit(false)
	animation.play("page_to_notes")
	animation.seek(length-at,true)

func sync_world(show_map: bool, phase: int, loupe := false) -> void:
	if phase != 2:
		if phase != _world_phase: reset()
	elif busy and not show_map and _target_map: return_to_notes()
	elif not busy and displaying_map != show_map: transition_to(show_map)
	if phase == 2 and not busy: set_loupe(show_map and loupe)
	_world_phase = phase
