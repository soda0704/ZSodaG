extends Node3D
## Native hinge animations. Runtime only supplies textures and requests states.
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
@export var lens_window := Vector2(.1285714,.1782178)

func _ready() -> void:
	animation.animation_finished.connect(_on_animation_finished)
	$LoupeAnimation.animation_finished.connect(func(clip):
		if clip == &"lower" and not loupe_active:
			$LoupeAim.hide()
			if is_instance_valid(magnifier): magnifier.hide())
	reset()

func bind_ink(texture: Texture2D, rect: Rect2) -> void:
	for tile in $MapFold.find_children("*", "MeshInstance3D", true, false):
		var material: ShaderMaterial = tile.material_override
		material.set_shader_parameter("ink_texture", texture)
		material.set_shader_parameter("source_rect", Vector4(rect.position.x,rect.position.y,rect.size.x,rect.size.y))
		material.set_shader_parameter("paper_source_rect", Vector4(rect.position.x,rect.position.y,rect.size.x,rect.size.y))
	_map_rect = Rect2(rect.position*atlas_size,rect.size*atlas_size)
	_live_atlas = true
	if _lens_material != null:
		_lens_material.set_shader_parameter("ink_texture",texture)
		_lens_material.set_shader_parameter("window_extent",lens_window)
	set_loupe_focus(_map_rect.get_center())

func configure_grip(pose: Transform3D) -> void:
	if pose != Transform3D.IDENTITY: $LoupeAim/Lift/RightGrip.transform = pose

func configure_magnifier(visual: Node3D, pose: Transform3D) -> void:
	magnifier = visual
	magnifier.transform = pose.affine_inverse()
	magnifier.hide()
	_lens_material = magnifier.get_node("Lens").material_override
	_lens_material.set_shader_parameter("window_extent",lens_window/(_map_rect.size/atlas_size))
	var skeleton := magnifier.get_parent().get_parent().get_parent() as Skeleton3D
	if not skeleton.skeleton_updated.is_connected(_sync_lens_focus): skeleton.skeleton_updated.connect(_sync_lens_focus)

func _sync_lens_focus() -> void:
	if not loupe_active or not is_instance_valid(magnifier): return
	var at := to_local(magnifier.global_position)
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		var eye := to_local(camera.global_position)
		var ray := at-eye
		if absf(ray.z)>.00001: at = eye+ray*(($MapFold.position.z-eye.z)/ray.z)
	var point := Vector2((at.x/sheet_width+1)*atlas_size.x*.5,(.5-at.y/sheet_height)*atlas_size.y)
	_lens_material.set_shader_parameter("focus_atlas",point/atlas_size if _live_atlas else (point-_map_rect.position)/_map_rect.size)

func bind_paper(texture: Texture2D, rect: Vector4) -> void:
	for mesh in find_children("*","MeshInstance3D",true,false):
		if mesh.material_override is ShaderMaterial:
			mesh.material_override.set_shader_parameter("paper_texture",texture)
			mesh.material_override.set_shader_parameter("paper_rect",rect)

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

func bind_turn_texture(texture: Texture2D) -> void:
	var material: ShaderMaterial = $TurnPivot/Page.material_override
	material.set_shader_parameter("ink_texture", texture)
	material.set_shader_parameter("source_rect", Vector4(.5,0,.5,1))

func transition_to(show_map: bool) -> void:
	if busy or show_map == displaying_map: return
	set_loupe(false)
	busy = true
	_target_map = show_map
	animation.play("page_to_map" if show_map else "fold")

func _on_animation_finished(clip: StringName) -> void:
	if not busy: return
	match clip:
		&"page_to_map":
			displaying_map = true
			content_requested.emit(true)
			animation.play("unfold")
		&"fold":
			animation.play("page_to_notes")
		&"unfold", &"page_to_notes":
			if clip == &"page_to_notes": content_requested.emit(false)
			displaying_map = _target_map
			busy = false
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
	animation.play("unfold")
	animation.seek(animation.current_animation_length,true)
	animation.advance(0)
	animation.pause()

func return_to_notes() -> void:
	if not busy:
		transition_to(false)
		return
	_target_map = false
	var at := animation.current_animation_position
	if animation.current_animation == "unfold":
		animation.play("fold")
		animation.seek(1.35-at,true)
	elif animation.current_animation == "page_to_map":
		content_requested.emit(false)
		animation.play("page_to_notes")
		animation.seek(.72-at,true)

func sync_world(show_map: bool, phase: int, loupe := false) -> void:
	if phase != 2:
		if phase != _world_phase: reset()
	elif busy and not show_map and _target_map: return_to_notes()
	elif not busy and displaying_map != show_map: transition_to(show_map)
	if phase == 2 and not busy: set_loupe(show_map and loupe)
	_world_phase = phase
