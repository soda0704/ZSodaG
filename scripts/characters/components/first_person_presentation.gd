class_name GameFirstPersonPresentation
extends Node3D
## Owner-only presentation. No RPCs, gameplay rays or bone Euler animation here.

const VIEW_LAYER := 1 << 19
const LOCAL_BODY_LAYER := 1 << 17
const KINDS := {&"m4a1":"Rifle",&"pistol":"Pistol",&"flashlight":"Flashlight",&"kitchen_knife":"Knife",&"fuse":"Fuse",&"fuel_can":"Fuel"}
@export var angular_mass := 0.014
@export var max_lag_degrees := 1.5
@export var settling_frequency := 13.0

var model: Node3D
var tree: AnimationTree
var camera: Camera3D
var view_camera: Camera3D
var viewport: SubViewport
var overlay: CanvasLayer
var context: Dictionary = {}
var kind := "Relaxed"
var _journal_phase := 0
var _ads := 0.0
var _last_basis := Basis.IDENTITY
var _sampled := false
var _offset := Vector3.ZERO
var _offset_velocity := Vector3.ZERO
var _angle := Vector3.ZERO
var _angle_velocity := Vector3.ZERO
var _step_phase := 0.0
var _grounded := true
var _disabled := false
var _external_view := false
var _hidden_geometry: Dictionary = {}
var _book_elapsed:=0.0
var _empty_elapsed := 1.0
var _environment_source: Environment
var _view_environment: Environment
var _environment_dirty:=true

func initialize(asset: PackedScene, owner_camera: Camera3D) -> void:
	camera=owner_camera
	model=asset.instantiate()
	add_child(model)
	tree=model.get_node("AnimationTree")
	tree.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.active=true
	# Separate depth buffer keeps hands out of walls without changing the shot.
	# Shared World3D supplies actual environmental lighting to the viewmodel.
	overlay=CanvasLayer.new(); overlay.name="ViewmodelComposite"; overlay.layer=4
	add_child(overlay)
	var surface:=SubViewportContainer.new(); surface.mouse_filter=Control.MOUSE_FILTER_IGNORE
	overlay.add_child(surface); surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); surface.stretch=true
	viewport=SubViewport.new(); viewport.name="ViewmodelViewport"; viewport.transparent_bg=true
	viewport.world_3d=camera.get_world_3d()
	viewport.handle_input_locally=false; viewport.msaa_3d=Viewport.MSAA_4X
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	surface.add_child(viewport)
	view_camera=Camera3D.new(); view_camera.cull_mask=VIEW_LAYER; view_camera.near=0.01; view_camera.far=5.0
	view_camera.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewport.add_child(view_camera); view_camera.current=true
	camera.cull_mask &= ~(VIEW_LAYER|(1<<18))
	# Godot also applies camera layers to shadow casters. The local body is
	# SHADOWS_ONLY, so this layer preserves its shadow without drawing its mesh.
	camera.cull_mask |= LOCAL_BODY_LAYER
	var fill:=OmniLight3D.new(); fill.name="ViewmodelFill"; fill.light_cull_mask=VIEW_LAYER
	fill.layers=VIEW_LAYER
	fill.light_energy=0.45; fill.omni_range=2.0; fill.position=Vector3(0,0.08,0.12); add_child(fill)
	# Camera visibility layers also cull Light3D instances. Include existing and
	# subsequently spawned lights in the view pass, without exposing world meshes.
	for light in get_tree().root.find_children("*","Light3D",true,false): _include_light(light)
	get_tree().node_added.connect(_include_light)
	_refresh_visibility()

func _include_light(node: Node) -> void:
	if node is Light3D:
		node.layers|=VIEW_LAYER; node.light_cull_mask|=VIEW_LAYER

func update_context(values: Dictionary) -> void:
	context=values.duplicate()

func _process(delta: float) -> void:
	if model==null or _disabled: return
	var animation_delta:=delta
	delta=minf(delta,0.04)
	var next: String=KINDS.get(context.get("held_item",&""),"Relaxed")
	if context.get("carrying",false): next="Carry"
	if next!=kind:
		kind=next; tree.set("parameters/Equipment/transition_request",kind)
		cancel_action()
		if kind=="Relaxed":
			_empty_elapsed=0.0
			tree.set("parameters/Draw/request",AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
			tree.set("parameters/Stow/request",AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		else:
			tree.set("parameters/Stow/request",AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
			tree.set("parameters/Draw/request",AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_empty_elapsed+=animation_delta
	var book_phase: int=context.get("journal_phase",0)
	if book_phase!=_journal_phase:
		var playback: AnimationNodeStateMachinePlayback=tree.get("parameters/Journal/playback")
		if book_phase==1:
			var seek:=0.88*(1-clampf(_book_elapsed/0.72,0,1)) if _journal_phase==3 else 0.0
			cancel_action(); playback.start("JournalOpen"); tree.set("parameters/Journal/JournalOpen/Time/seek_request",seek); _book_elapsed=seek
		elif book_phase==2: playback.travel("JournalReading")
		elif book_phase==3:
			var seek:=0.72*(1-clampf(_book_elapsed/0.88,0,1)) if _journal_phase==1 else 0.0
			playback.travel("JournalClose"); tree.set("parameters/Journal/JournalClose/Time/seek_request",seek); _book_elapsed=seek
		elif book_phase==0 and kind!="Relaxed":
			tree.set("parameters/Draw/request",AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		_journal_phase=book_phase
	_book_elapsed+=animation_delta
	var book_weight: float=tree.get("parameters/BookBlend/blend_amount")
	tree.set("parameters/BookBlend/blend_amount",move_toward(book_weight,1.0 if book_phase>0 else 0.0,animation_delta*12))
	model.get_node("Journal").visible=book_phase>0 or book_weight>0.01
	var aiming: bool=context.get("aiming",false) and kind in ["Rifle","Pistol"] and book_phase==0 and not context.get("reloading",false)
	_ads=move_toward(_ads,1.0 if aiming else 0.0,delta*5.5)
	for label in ["Rifle","Pistol"]: tree.set("parameters/%s/blend_position"%label,_ads)
	var velocity: Vector3=context.get("velocity",Vector3.ZERO)
	var local_velocity:=camera.global_basis.inverse()*velocity
	var speed:=Vector2(velocity.x,velocity.z).length()
	var grounded: bool=context.get("grounded",true)
	if not _grounded and grounded: _offset_velocity.y-=0.16
	_grounded=grounded
	_step_phase+=delta*(2.10 if context.get("sprinting",false) else 1.65)*TAU*clampf(speed/4.0,0,1.25)
	var attenuation:=lerpf(1.0,0.15,_ads)*(0.15 if book_phase>0 else 1.0)
	var sway:=Vector3(sin(_step_phase)*0.0035,cos(_step_phase*2)*0.003,0)*minf(speed/4,1)*attenuation if grounded else Vector3.ZERO
	var linear_target:=Vector3(-local_velocity.x*0.0015,0,local_velocity.z*0.001)*attenuation+sway
	var rotation_target:=Vector3.ZERO
	if _sampled:
		var turn:=(_last_basis.inverse()*camera.global_basis).get_euler()/maxf(delta,0.001)
		rotation_target=(-turn*angular_mass).limit_length(deg_to_rad(max_lag_degrees))*attenuation
	_last_basis=camera.global_basis; _sampled=true
	# Critically damped springs on the complete rig preserve both item contacts.
	var omega:=settling_frequency
	_offset_velocity+=(linear_target-_offset)*omega*omega*delta-_offset_velocity*2*omega*delta
	_offset+=_offset_velocity*delta
	_angle_velocity+=(rotation_target-_angle)*omega*omega*delta-_angle_velocity*2*omega*delta
	_angle+=_angle_velocity*delta
	position=_offset.limit_length(0.025); rotation=_angle.limit_length(deg_to_rad(2.0))
	_refresh_visibility()
	view_camera.global_transform=camera.global_transform
	_sync_environment()
	view_camera.fov=lerpf(lerpf(camera.fov,camera.fov-6.0,_ads),45.0,book_weight)
	# Only the spring integration needs a bounded step. Animation playback must
	# keep real time even on a heavy level at less than 25 rendered frames/sec.
	tree.advance(animation_delta)
	update_grips(model,kind,book_phase,context.get("reloading",false),delta)

func _environment_changed() -> void:
	_environment_dirty=true

func _sync_environment() -> void:
	var source:=camera.get_world_3d().environment
	if source!=_environment_source:
		if _environment_source!=null and _environment_source.changed.is_connected(_environment_changed): _environment_source.changed.disconnect(_environment_changed)
		_environment_source=source
		if source!=null: source.changed.connect(_environment_changed)
		_environment_dirty=true
	if _environment_dirty:
		_view_environment=source.duplicate() as Environment if source!=null else null
		# The transparent depth pass cannot support SSR. Everything else follows
		# the actual environment, including changes made in graphics settings.
		if _view_environment!=null: _view_environment.ssr_enabled=false
		view_camera.environment=_view_environment
		_environment_dirty=false

static func update_grips(instance: Node3D, equipment_kind: String, journal_phase: int, reloading: bool, delta: float) -> void:
	var sk: Skeleton3D=instance.get_node("Skeleton3D")
	var book: Node3D=instance.get_node("Journal")
	var sockets: Node3D=sk.get_node("RightHand/Equipment")
	var left_ik: TwoBoneIK3D=sk.get_node("SupportHandIK")
	var right_ik: TwoBoneIK3D=sk.get_node("RightGripIK")
	var weight:=1-exp(-18*delta)
	for side in ["Left","Right"]:
		var target: Node3D=sk.get_node(side+"WristTarget")
		var ik:=left_ik if side=="Left" else right_ik
		var marker: Node3D
		if journal_phase>0: marker=book.get_node(side+"Grip")
		elif side=="Left" and equipment_kind in ["Rifle","Pistol"] and not reloading:
			marker=sockets.get_node(("m4a1" if equipment_kind=="Rifle" else "pistol")+"/LeftHandGrip")
		var amount:=1.0 if marker!=null else 0.0
		if marker!=null:
			target.transform=sk.global_transform.affine_inverse()*marker.global_transform
			ik.set_target_node(0,ik.get_path_to(target))
		ik.active=true; ik.influence=lerpf(ik.influence,amount,weight)
		# Position IK preserves the authored hand/forearm relationship.
		# Wrist orientation belongs to the clip, never a global CopyTransform.

func action(item: String, label: String) -> void:
	if _journal_phase>0 or item=="Relaxed": return
	if label=="Recoil":
		tree.set("parameters/Recoil/transition_request",item)
		tree.set("parameters/Kick/request",AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	else:
		tree.set("parameters/Action/transition_request",item+label)
		tree.set("parameters/Handling/request",AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

func cancel_action() -> void:
	tree.set("parameters/Handling/request",AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	tree.set("parameters/Kick/request",AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)

func _refresh_visibility() -> void:
	var book_weight: float = tree.get("parameters/BookBlend/blend_amount")
	model.visible = not _disabled and (kind != "Relaxed" or _empty_elapsed < 0.32 or _journal_phase > 0 or book_weight > 0.01) and not context.get("driving", false) and not context.get("sleeping", false)
	var draw_view := model.visible and camera.current and not _external_view
	# Hide renderable geometry, including held items, from every camera.
	# Keep the gameplay flashlight's Light3D children active in the shared world.
	for geometry: GeometryInstance3D in model.find_children("*", "GeometryInstance3D", true, false):
		var id := geometry.get_instance_id()
		if draw_view:
			if _hidden_geometry.has(id):
				geometry.visible = _hidden_geometry[id]
				_hidden_geometry.erase(id)
		else:
			if not _hidden_geometry.has(id) or geometry.visible: _hidden_geometry[id] = geometry.visible
			geometry.hide()
	overlay.visible = draw_view
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if draw_view else SubViewport.UPDATE_DISABLED

func set_external_view(value: bool) -> void:
	_external_view = value
	_refresh_visibility()

func set_dead(value: bool) -> void:
	_disabled=value
	if not value: _sampled=false; context.clear(); _offset=Vector3.ZERO; _angle=Vector3.ZERO
	_refresh_visibility()

func _exit_tree() -> void:
	if is_instance_valid(overlay): overlay.queue_free()
