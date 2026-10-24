class_name GameFirstPersonPresentation
extends Node3D
## Owner-only presentation. No RPCs, gameplay rays or bone Euler animation here.

const VIEW_LAYER := 1 << 19
const LOCAL_BODY_LAYER := 1 << 17
const KINDS := {&"flamethrower":"Flamethrower",&"m4a1":"Rifle",&"pistol":"Pistol",&"flashlight":"Flashlight",&"kitchen_knife":"Knife",&"fuse":"Fuse",&"seed_packet":"Fuse",&"fuel_can":"Fuel"}
@export var angular_mass := 0.014
@export var max_lag_degrees := 1.5
@export var settling_frequency := 13.0
@export_range(35.0, 90.0) var viewmodel_fov := 55.0
@export_range(35.0, 90.0) var viewmodel_ads_fov := 54.0
@export_range(0.0, 12.0) var viewmodel_framing_pitch := 8.0

var model: Node3D
var tree: AnimationTree
var recoil_player: AnimationPlayer
var aim_pivot: Node3D
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
var _heavy_alignment := 0.0
var _hands_in_world := false
var _environment_source: Environment
var _view_environment: Environment
var _environment_dirty:=true
var _view_frame := Transform3D.IDENTITY
var _item_offsets: Dictionary = {}
var _lighting_fill: DirectionalLight3D
var _view_world_root:Node3D
var _world_light_instances:Dictionary={}
var _model_lights: Array[Light3D] = []
var _model_geometry: Array[GeometryInstance3D] = []
var _environment_keys: Array[StringName] = []

func initialize(asset: PackedScene, owner_camera: Camera3D, item_offsets: Dictionary = {}) -> void:
	camera=owner_camera
	# OFF on the model alone still inherits an interpolated moving ancestor.
	# Keep the rendered view rig independent of the physics camera hierarchy.
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_view_frame = camera.get_global_transform_interpolated()
	global_transform = _view_frame
	model=asset.instantiate()
	_item_offsets=item_offsets
	aim_pivot=Node3D.new();aim_pivot.name="AimAlignment";add_child(aim_pivot)
	var recoil_pivot:=Node3D.new();recoil_pivot.name="RecoilPivot";aim_pivot.add_child(recoil_pivot)
	recoil_pivot.add_child(model)
	for weapon_name in ["pistol","m4a1"]:
		var source:Node3D=load("res://scenes/objects/items/"+weapon_name+"_model.tscn").instantiate()
		var visual:Node3D=model.get_node("Skeleton3D/RightHand/Equipment/"+weapon_name)
		for sight_name in ["RearSight","FrontSight"]:
			var marker:Node3D=visual.get_node_or_null(sight_name)
			if marker==null:
				marker=Marker3D.new();marker.name=sight_name;visual.add_child(marker)
			marker.transform=source.get_node(sight_name).transform
		source.free()
	recoil_player=AnimationPlayer.new();recoil_pivot.add_child(recoil_player)
	var recoil_clip:=Animation.new();recoil_clip.length=0.24
	var recoil_rotation:=recoil_clip.add_track(Animation.TYPE_ROTATION_3D);recoil_clip.track_set_path(recoil_rotation,NodePath("."))
	var recoil_position:=recoil_clip.add_track(Animation.TYPE_POSITION_3D);recoil_clip.track_set_path(recoil_position,NodePath("."))
	for sample in 25:
		var t:float=sample*0.01
		var amount:float=smoothstep(0.0,0.04,t)*(1.0-smoothstep(0.04,0.24,t))
		recoil_clip.rotation_track_insert_key(recoil_rotation,t,Quaternion(Vector3.RIGHT,deg_to_rad(0.8)*amount))
		recoil_clip.position_track_insert_key(recoil_position,t,Vector3(0,0,0.006*amount))
	var recoil_library:=AnimationLibrary.new();recoil_library.add_animation("Pistol",recoil_clip);recoil_player.add_animation_library("",recoil_library)
	tree=model.get_node("AnimationTree")
	tree.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.active=true
	# Separate depth buffer keeps hands out of walls without changing the shot.
	# An isolated world avoids culling and lighting the entire base twice.
	overlay=CanvasLayer.new(); overlay.name="ViewmodelComposite"; overlay.layer=4
	add_child(overlay)
	var surface:=TextureRect.new(); surface.mouse_filter=Control.MOUSE_FILTER_IGNORE
	surface.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	surface.stretch_mode=TextureRect.STRETCH_SCALE
	overlay.add_child(surface); surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport=SubViewport.new(); viewport.name="ViewmodelViewport"; viewport.transparent_bg=true
	viewport.world_3d=World3D.new()
	viewport.handle_input_locally=false
	viewport.msaa_3d=camera.get_viewport().msaa_3d
	viewport.screen_space_aa=camera.get_viewport().screen_space_aa
	# The view rig never renders the world's shadow maps a second time.
	viewport.positional_shadow_atlas_size=0
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	overlay.add_child(viewport)
	surface.texture=viewport.get_texture()
	_sync_view_resolution()
	_view_world_root=Node3D.new();_view_world_root.name="ViewRig"
	_view_world_root.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewport.add_child(_view_world_root)
	_view_world_root.global_transform=global_transform
	aim_pivot.reparent(_view_world_root,false)
	view_camera=Camera3D.new(); view_camera.cull_mask=VIEW_LAYER; view_camera.near=0.01; view_camera.far=5.0
	view_camera.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewport.add_child(view_camera); view_camera.current=true
	camera.cull_mask &= ~(VIEW_LAYER|(1<<18))
	# Godot also applies camera layers to shadow casters. The local body is
	# SHADOWS_ONLY, so this layer preserves its shadow without drawing its mesh.
	camera.cull_mask |= LOCAL_BODY_LAYER
	_lighting_fill=DirectionalLight3D.new()
	_lighting_fill.name="ViewLighting"
	_lighting_fill.set_meta("world_lighting",true)
	_lighting_fill.layers=VIEW_LAYER; _lighting_fill.light_cull_mask=VIEW_LAYER
	_lighting_fill.light_energy=0.0; _lighting_fill.shadow_enabled=false
	_lighting_fill.light_indirect_energy=0.0
	_lighting_fill.light_volumetric_fog_energy=0.0
	_lighting_fill.rotation_degrees=Vector3(-25,-20,0)
	_view_world_root.add_child(_lighting_fill)
	# Keep the exact live membership, including dynamically attached equipment.
	# Traversing the entire skeleton twice per frame is unnecessary.
	get_tree().node_added.connect(_register_model_node)
	get_tree().node_removed.connect(_unregister_model_node)
	for node in model.find_children("*", "Light3D", true, false): _register_model_node(node)
	for node in model.find_children("*", "GeometryInstance3D", true, false): _register_model_node(node)
	_refresh_visibility()

func _register_model_node(node: Node) -> void:
	if not (node is Light3D or node is GeometryInstance3D) or not model.is_ancestor_of(node): return
	if node is Light3D and not _model_lights.has(node): _model_lights.append(node)
	if node is GeometryInstance3D and not _model_geometry.has(node): _model_geometry.append(node)

func _unregister_model_node(node: Node) -> void:
	if node is Light3D: _model_lights.erase(node)
	if node is GeometryInstance3D:
		_model_geometry.erase(node)
		if _hidden_geometry.has(node.get_instance_id()): node.visible = _hidden_geometry[node.get_instance_id()]
		_hidden_geometry.erase(node.get_instance_id())

func update_context(values: Dictionary) -> void:
	context=values.duplicate()

func _process(delta: float) -> void:
	if model==null or _disabled: return
	_view_frame = camera.get_global_transform_interpolated()
	_sync_view_resolution()
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
	var aiming: bool=context.get("aiming",false) and context.get("held_item",&"") != &"flamethrower" and kind in ["Rifle","Pistol"] and book_phase==0 and not context.get("reloading",false)
	_ads=move_toward(_ads,1.0 if aiming else 0.0,delta*5.5)
	for label in ["Rifle","Pistol"]: tree.set("parameters/%s/blend_position"%label,_ads)
	var velocity: Vector3=context.get("velocity",Vector3.ZERO)
	var local_velocity:=_view_frame.basis.inverse()*velocity
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
		var turn:=(_last_basis.inverse()*_view_frame.basis).get_euler()/maxf(delta,0.001)
		rotation_target=(-turn*angular_mass).limit_length(deg_to_rad(max_lag_degrees))*attenuation
	_last_basis=_view_frame.basis; _sampled=true
	# Critically damped springs on the complete rig preserve both item contacts.
	var omega:=settling_frequency
	_offset_velocity+=(linear_target-_offset)*omega*omega*delta-_offset_velocity*2*omega*delta
	_offset+=_offset_velocity*delta
	_angle_velocity+=(rotation_target-_angle)*omega*omega*delta-_angle_velocity*2*omega*delta
	_angle+=_angle_velocity*delta
	global_transform = _view_frame * Transform3D(
		Basis.from_euler(_angle.limit_length(deg_to_rad(2.0))),
		_offset.limit_length(0.025)
	)
	_heavy_alignment = move_toward(_heavy_alignment, 1.0 if context.get("heavy_carry", false) else 0.0, animation_delta * 8.0)
	if _heavy_alignment > 0.0:
		# World furniture stays in the gameplay world. Match its projection and
		# keep the authored carrying pose on the body when the player looks down.
		# The model's native root offset supplies the anatomical origin.
		var body_frame: Transform3D = context.get("body_transform", _view_frame)
		global_transform = global_transform.interpolate_with(body_frame * model.transform.affine_inverse(), _heavy_alignment)
	_view_world_root.global_transform=global_transform
	_refresh_visibility()
	view_camera.global_transform=_view_frame
	view_camera.global_basis=_view_frame.basis*Basis(Vector3.RIGHT,deg_to_rad(-viewmodel_framing_pitch)*(1.0-_ads)*(1.0-book_weight)*(1.0-_heavy_alignment))
	var item_offset: Vector3=_item_offsets.get(context.get("held_item",&""),Vector3.ZERO)
	_sync_environment()
	_update_lighting(delta)
	view_camera.fov=lerpf(lerpf(viewmodel_fov,viewmodel_ads_fov,_ads),45.0,book_weight)
	view_camera.fov=lerpf(view_camera.fov, camera.fov, _heavy_alignment)
	# Only the spring integration needs a bounded step. Animation playback must
	# keep real time even on a heavy level at less than 25 rendered frames/sec.
	var offhand: bool = context.get("offhand_flashlight", false) and book_phase == 0 and not context.get("reloading", false) and not context.get("carrying", false) and not context.get("driving", false) and not context.get("sleeping", false)
	tree.set("parameters/OffhandTorch/blend_amount", move_toward(float(tree.get("parameters/OffhandTorch/blend_amount")), 1.0 if offhand else 0.0, animation_delta * 8.0))
	tree.set("parameters/OffhandAim/blend_position", 0.0)
	update_offer_tree(tree, context, animation_delta)
	tree.advance(animation_delta)
	update_grips(model,kind,book_phase,context.get("reloading",false),delta,offhand,context.get("held_item",&""),context.get("heavy_targets",{}))
	_align_weapon_sights()
	# Apply framing after animation evaluation, which restores the model root.
	aim_pivot.position+=item_offset*(1.0-book_weight)
	_sync_world_light_instances()

func _sync_view_resolution() -> void:
	# UI uses a fixed 1920x1080 canvas. Its logical size must not force an
	# oversized 3D render target when the actual game window is smaller.
	var output:Vector2i=camera.get_viewport().get("size")
	output=Vector2i(maxi(output.x,2),maxi(output.y,2))
	if viewport.size!=output:viewport.size=output
	var scale:=camera.get_viewport().scaling_3d_scale
	if not is_equal_approx(viewport.scaling_3d_scale,scale):viewport.scaling_3d_scale=scale

func _sync_world_light_instances() -> void:
	# Logical equipment and its sockets stay together. Only the lights' render
	# instances join the gameplay scenario, keeping their exact animated pose,
	# battery state and visibility without duplicating lights or shadow maps.
	for light in _model_lights:
		var instance:=light.get_instance()
		if not _world_light_instances.has(instance):
			RenderingServer.instance_set_scenario(instance,camera.get_world_3d().scenario)
			_world_light_instances[instance]=true
			# Leaving the tree rebinds a Light3D to its viewport scenario even
			# when its RID survives. Re-register after any reparent/re-entry.
			light.tree_exited.connect(_forget_world_light.bind(instance), CONNECT_ONE_SHOT)

func _forget_world_light(instance: RID) -> void:
	_world_light_instances.erase(instance)

func _align_weapon_sights() -> void:
	aim_pivot.transform=Transform3D.IDENTITY
	if kind not in ["Pistol","Rifle"] or _ads<=0.001: return
	var recoil_pivot:Node3D=recoil_player.get_parent()
	var kick_transform:=recoil_pivot.transform
	recoil_pivot.transform=Transform3D.IDENTITY
	var sk:Skeleton3D=model.get_node("Skeleton3D")
	sk.force_update_all_bone_transforms()
	# Use the authored hand socket directly; BoneAttachment updates can lag
	# behind manual AnimationTree advancement by one frame.
	var sockets:Node3D=sk.get_node("RightHand/Equipment")
	var pistol:Node3D=sockets.get_node("pistol" if kind=="Pistol" else "m4a1")
	var gun:Transform3D=sk.global_transform*sk.get_bone_global_pose(sk.find_bone("RightHand"))*sockets.transform*pistol.transform
	var rear:Vector3=pistol.get_node("RearSight").position if pistol.has_node("RearSight") else Vector3(0,.067,.025) if kind=="Pistol" else Vector3(-.0083,.100,-.008)
	var front:Vector3=pistol.get_node("FrontSight").position if pistol.has_node("FrontSight") else Vector3(0,.067,-.17) if kind=="Pistol" else Vector3(-.0083,.092,-.403)
	var sight_frame:=Basis.looking_at((front-rear).normalized(),Vector3.UP)
	var weapon_basis:Basis=_view_frame.basis*sight_frame.inverse()
	var distance:float=.38 if kind=="Pistol" else .40
	var desired:=Transform3D(weapon_basis,_view_frame.origin+_view_frame.basis*Vector3(0,0,-distance)-weapon_basis*rear)
	var aligned:Transform3D=global_transform.affine_inverse()*(desired*gun.affine_inverse())*global_transform
	aim_pivot.transform=Transform3D.IDENTITY.interpolate_with(aligned,_ads)
	recoil_pivot.transform=kick_transform

func _environment_changed() -> void:
	_environment_dirty=true

func _sync_environment() -> void:
	var source:=camera.environment if camera.environment!=null else camera.get_world_3d().environment
	if source!=_environment_source:
		if _environment_source!=null and _environment_source.changed.is_connected(_environment_changed): _environment_source.changed.disconnect(_environment_changed)
		_environment_source=source
		if source!=null: source.changed.connect(_environment_changed)
		_view_environment=source.duplicate() as Environment if source!=null else null
		if _view_environment!=null:
			_view_environment.volumetric_fog_enabled=false
			_view_environment.fog_enabled=false
			_view_environment.ssao_enabled=false
			_view_environment.ssr_enabled=false
		view_camera.environment=_view_environment
		_environment_keys.clear()
		if source != null:
			for property in source.get_property_list():
				var key: StringName = property.name
				if not (property.usage & PROPERTY_USAGE_STORAGE) or str(key).begins_with("volumetric_fog") or str(key).begins_with("fog_") or str(key).begins_with("ssao_") or str(key).begins_with("ssr_"): continue
				_environment_keys.append(key)
		_environment_dirty=true
	if _environment_dirty:
		# Keep one GPU environment. Roof transitions must not allocate a new
		# environment and its render bindings every frame.
		if source!=null and _view_environment!=null:
			for key in _environment_keys:
				var value:Variant=source.get(key)
				if _view_environment.get(key)!=value:_view_environment.set(key,value)
		_environment_dirty=false

func _update_lighting(delta: float) -> void:
	var lighting := get_tree().get_first_node_in_group("world_lighting")
	var target := Color(0.02,0.025,0.03)
	if lighting != null: target=lighting.sample_view_light(camera)
	var magnitude:=maxf(target.r,maxf(target.g,target.b))
	_lighting_fill.light_color=target/magnitude if magnitude>0.0001 else Color.WHITE
	_lighting_fill.light_energy=lerpf(_lighting_fill.light_energy,magnitude,1.0-exp(-8.0*delta))

static func update_offer_tree(target_tree: AnimationTree, values: Dictionary, delta: float) -> void:
	if not target_tree.tree_root.has_node("OfferBlend"): return
	var active: bool = values.get("offering", false) and int(values.get("journal_phase", 0)) == 0
	var label: String = "Heavy" if values.get("heavy_carry", false) else "Pocket" if values.get("offer_pocket", false) else KINDS.get(values.get("held_item", &""), "Pocket")
	target_tree.set("parameters/OfferPose/transition_request", label)
	target_tree.set("parameters/OfferBlend/blend_amount", move_toward(float(target_tree.get("parameters/OfferBlend/blend_amount")), 1.0 if active else 0.0, delta * 6))

static func update_grips(instance: Node3D, equipment_kind: String, journal_phase: int, reloading: bool, delta: float, offhand_flashlight := false, held_item: StringName = &"", heavy_targets: Dictionary = {}) -> void:
	var sk: Skeleton3D=instance.get_node("Skeleton3D")
	var book: Node3D=instance.get_node("Journal")
	var sockets: Node3D=sk.get_node("RightHand/Equipment")
	var left_ik: TwoBoneIK3D=sk.get_node("SupportHandIK")
	var right_ik: TwoBoneIK3D=sk.get_node("RightGripIK")
	var weight:=1-exp(-18*delta)
	var flame_wrist: CopyTransformModifier3D=sk.get_node_or_null("FlamethrowerWrist")
	if flame_wrist!=null:
		var hold:=equipment_kind=="Flamethrower" and journal_phase==0 and not reloading and not offhand_flashlight
		flame_wrist.influence=lerpf(flame_wrist.influence,1.0 if hold else 0.0,weight)
		sk.get_node("FlamethrowerSupportIK").influence=flame_wrist.influence
	for side in ["Left","Right"]:
		var target: Node3D=sk.get_node(side+"WristTarget")
		var ik:=left_ik if side=="Left" else right_ik
		var marker: Node3D
		if journal_phase>0: marker=book.get_node(side+"Grip")
		elif side=="Left" and equipment_kind in ["Rifle","Pistol"] and not reloading and not offhand_flashlight:
			marker=sockets.get_node(("flamethrower" if held_item == &"flamethrower" else "m4a1" if equipment_kind=="Rifle" else "pistol")+"/LeftHandGrip")
		var contact: Variant = heavy_targets.get(side)
		var amount:=1.0 if marker!=null or contact is Transform3D else 0.0
		if marker!=null:
			target.transform=sk.global_transform.affine_inverse()*marker.global_transform
			ik.set_target_node(0,ik.get_path_to(target))
		elif contact is Transform3D:
			target.transform=sk.global_transform.affine_inverse()*contact
			ik.set_target_node(0,ik.get_path_to(target))
		ik.active=true; ik.influence=lerpf(ik.influence,amount,weight)
		# Position IK preserves the authored hand/forearm relationship.
		# The flamethrower also has a native wrist constraint fitted to its tube.

func action(item: String, label: String) -> void:
	if _journal_phase>0 or item=="Relaxed": return
	if label=="Recoil":
		if item=="Pistol":
			recoil_player.stop();recoil_player.play("Pistol")
			return
		tree.set("parameters/Recoil/transition_request",item)
		tree.set("parameters/Kick/request",AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	else:
		var handling:AnimationNodeOneShot=tree.tree_root.get_node("Handling")
		handling.fadein_time=(0.16 if item=="Pistol" else 0.18) if label=="Reload" else 0.08
		handling.fadeout_time=(0.22 if item=="Pistol" else 0.24) if label=="Reload" else 0.16
		tree.set("parameters/Action/transition_request",item+label)
		tree.set("parameters/Handling/request",AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

func cancel_action() -> void:
	if recoil_player!=null:
		recoil_player.stop()
		(recoil_player.get_parent() as Node3D).transform=Transform3D.IDENTITY
	tree.set("parameters/Handling/request",AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	tree.set("parameters/Kick/request",AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)

func _refresh_visibility() -> void:
	var book_weight: float = tree.get("parameters/BookBlend/blend_amount")
	var offer_visible: bool = tree.tree_root.has_node("OfferBlend") and float(tree.get("parameters/OfferBlend/blend_amount")) > 0.001
	model.visible = not _disabled and (kind != "Relaxed" or _empty_elapsed < 0.32 or _journal_phase > 0 or book_weight > 0.01 or context.get("offering", false) or offer_visible) and not context.get("driving", false) and not context.get("sleeping", false)
	var draw_view := model.visible and camera.current and not _external_view
	var world_hands: bool = draw_view and context.get("heavy_carry", false)
	if world_hands != _hands_in_world:
		_hands_in_world = world_hands
		# Carrying hands share depth with furniture, so its seat can hide palms
		# underneath it. Normal weapons retain their separate viewmodel depth.
		var scenario := camera.get_world_3d().scenario if world_hands else viewport.find_world_3d().scenario
		for geometry in _model_geometry: RenderingServer.instance_set_scenario(geometry.get_instance(), scenario)
		if world_hands: camera.cull_mask |= VIEW_LAYER
		else: camera.cull_mask &= ~VIEW_LAYER
	# Hide renderable geometry, including held items, from every camera.
	# Gameplay light render instances remain in the main world.
	for geometry in _model_geometry:
		var id := geometry.get_instance_id()
		if draw_view:
			if _hidden_geometry.has(id):
				geometry.visible = _hidden_geometry[id]
				_hidden_geometry.erase(id)
		else:
			if not _hidden_geometry.has(id) or geometry.visible: _hidden_geometry[id] = geometry.visible
			geometry.hide()
	overlay.visible = draw_view and not world_hands
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if draw_view and not world_hands else SubViewport.UPDATE_DISABLED

func set_external_view(value: bool) -> void:
	_external_view = value
	_refresh_visibility()

func set_dead(value: bool) -> void:
	_disabled=value
	if not value: _sampled=false; context.clear(); _offset=Vector3.ZERO; _angle=Vector3.ZERO
	_refresh_visibility()

func _exit_tree() -> void:
	if is_instance_valid(camera): camera.cull_mask &= ~VIEW_LAYER
	if is_instance_valid(overlay): overlay.queue_free()

