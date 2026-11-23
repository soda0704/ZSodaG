extends SceneTree
var checks := 0
var failures := 0
var actor: GamePlayer
var output := "res://tools/.local/snow-material-review/captures/"
const Plan = preload("res://scripts/network/level_load_plan.gd")
const SnowDriftProfile := preload("res://scripts/effects/snow_drift_profile.gd")
const SnowDeformation := preload("res://scripts/effects/snow_deformation.gd")
func _initialize() -> void:
	var prefix := "user://snow_session_%d" % OS.get_process_id()
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING,prefix+".cfg")
	ProjectSettings.set_setting("northern_lab/testing/settings_path",prefix+".json")
	ProjectSettings.set_setting(JournalReadingStore.ROOT_SETTING,prefix)
	ProjectSettings.set_setting("northern_lab/testing/save_slots_root",prefix+"/slots")
	ProjectSettings.set_setting("northern_lab/testing/legacy_save_paths",{})
	if not OS.get_environment("NORTHERNLAB_EXPORT_CAPTURE_DIR").is_empty():output=OS.get_environment("NORTHERNLAB_EXPORT_CAPTURE_DIR")+"/"
	create_timer(110).timeout.connect(func():quit(2))
	run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func shot(label: String) -> void:
	await create_timer(0.65).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output+label+".png")

func hold_forward() -> void:
	# Focus changes can clear simulated Input actions while a graphical test is running.
	if not Input.is_action_pressed("move_forward"):
		Input.action_press("move_forward")

func check_snow_contact() -> void:
	var snow := SnowDeformation.new()
	var material := Terrain3DMaterial.new()
	# Cross the tile edge diagonally, as a straight path rarely follows the terrain grid.
	var start := Vector3(60, 2, 60)
	var finish := Vector3(68, 2, 68)
	snow.push_snow(start, finish, 1.0)
	var side := Vector2.ONE.normalized().orthogonal()
	var uniform_width := true
	for along in [0.25, 0.49, 0.50, 0.51, 0.75]:
		var point: Vector3 = start.lerp(finish, along)
		for offset in [-0.88, -0.24, 0.0, 0.24, 0.88]:
			var sample := Vector2(point.x, point.z) + side * float(offset)
			var key := Vector2i((sample / SnowDeformation.TILE_METRES).floor())
			var slot := snow._keys.find(key)
			if slot < 0:
				uniform_width = false
				continue
			var cell := Vector2i((sample - snow._origins[slot]) / SnowDeformation.PIXEL_SIZE)
			var compression := snow._atlas.get_pixelv(snow._atlas_origin(slot) + cell).r
			uniform_width = uniform_width and (compression > 0.95 if absf(offset) < 0.5 else compression < 0.02)
	check(uniform_width, "diagonal track stays the same width across snow tiles")
	var ahead := Vector2(finish.x, finish.z) + Vector2.ONE.normalized() * 0.24
	var ahead_key := Vector2i((ahead / SnowDeformation.TILE_METRES).floor())
	var ahead_slot := snow._keys.find(ahead_key)
	var ahead_cell := Vector2i((ahead - Vector2(ahead_key) * SnowDeformation.TILE_METRES) / SnowDeformation.PIXEL_SIZE)
	var ahead_color := snow._atlas.get_pixelv(snow._atlas_origin(ahead_slot) + ahead_cell)
	check(ahead_color.r + ahead_color.g < 0.01, "snow ahead of the final contact is untouched")
	snow.flush(material, 1.0)
	snow.flush(material, 44.0)
	check(snow._keys.count(SnowDeformation.EMPTY_TILE) == snow._keys.size(), "old tracks release all atlas slots")
	snow.push_snow(start, finish, 45.0)
	check(snow._keys.size() <= 4 and snow._keys.count(SnowDeformation.EMPTY_TILE) == 0, "later tracks reuse expired slots")

func run() -> void:
	check_snow_contact()
	DirAccess.make_dir_recursive_absolute(output)
	Engine.max_fps=60;root.size=Vector2i(1600,900);root.content_scale_size=root.size
	var menu=root.get_node("GameMenu")
	await menu.start_standalone_flow()
	var session=current_scene
	await session._enter_v3_level()
	var base=session.get_node("V3Level")
	actor=get_first_node_in_group("local_player")
	actor.survival.set_physics_process(false)
	var exterior=base.get_node("SnowExterior")
	var terrain=exterior.get_node("Terrain3D")
	var tracks=exterior.get_node("SnowTracks")
	check(tracks.is_physics_processing() and tracks._terrain==terrain,"track sampler reacquires Terrain3D after staged loading")
	# Use the current approach alignment for the straight-input footprint check.
	var at=Vector3(-66.4,0,49);at.y=terrain.data.get_height(at)+0.1
	actor.teleport_authoritative(at,0)
	for frame in 20:await physics_frame
	var before:int=tracks._marks.size()
	for frame in 180:
		hold_forward()
		await physics_frame
	Input.action_release("move_forward")
	for frame in 10:await physics_frame
	check(actor.global_position.z<at.z-5,"normal forward input actually moves the player on snow")
	check(tracks._marks.size()>=before+8,"normal walking leaves boot prints without calling the sampler directly")
	print("WALK position=",actor.global_position," marks=",tracks._marks.size()-before)
	var profile := SnowDriftProfile.new()
	var deep := Vector3.ZERO
	var depth := 0.0
	for x in range(45, 110, 2):
		for z in range(-105, -55, 2):
			var candidate := profile.depth_for_walking(Vector2(x, z))
			var point := Vector3(x, 0, z)
			var height: float = terrain.data.get_height(point)
			if candidate > depth and is_finite(height):
				depth = candidate
				deep = Vector3(x, height + 0.12, z)
	actor.teleport_authoritative(deep, 0)
	check(depth > 0.65 and depth <= SnowDriftProfile.DEPTH_RANGE, "interactive snow forms deep drifts within the one-metre cap")
	for frame in 35: await physics_frame
	for frame in 30:
		hold_forward()
		await physics_frame
	Input.action_release("move_forward")
	print("DEEP SNOW profile=", depth, " position=", actor.global_position, " floor=", actor.is_on_floor(), " resistance=", actor._locomotion._snow_resistance)
	check(actor._locomotion._snow_resistance > 0.4, "deep snow applies movement resistance on actual terrain")
	var deep_end := actor.global_position
	var snow := tracks._snow_deformation as RefCounted
	var midpoint := deep.lerp(deep_end, 0.5)
	var full_width := deep.distance_to(deep_end) > 0.5
	var span := Vector2(deep_end.x - deep.x, deep_end.z - deep.z).normalized().orthogonal()
	for offset in [-0.24, 0.0, 0.24]:
		var sample := Vector2(midpoint.x, midpoint.z) + span * float(offset)
		var key := Vector2i((sample / 16.0).floor())
		var slot: int = snow._keys.find(key)
		if slot < 0:
			full_width = false
			continue
		var pixel: Vector2i = snow._atlas_origin(slot) + Vector2i((sample - Vector2(key) * 16.0) * 12.0)
		full_width = full_width and snow._atlas.get_pixelv(pixel).r > 0.95
	check(full_width, "walking through a tall drift fully compresses the center across the player's width")
	var fine_count := int(terrain.material.get_shader_param("fine_snow_tile_count"))
	check(fine_count > 0 and fine_count <= 4, "nearby snow uses a bounded pool of high-resolution surfaces")
	actor.set_physics_process(false)
	exterior.get_node("Blizzard").enabled = false
	actor.get_node("PlayerUI/CameraPostProcess").effect_enabled = false
	actor.head.look_at(deep + Vector3.DOWN * 0.3)
	await shot("deep-snow-rounded-track")
	actor.set_physics_process(true)
	var sled := preload("res://scenes/objects/vehicles/snowmobile.tscn").instantiate() as CharacterBody3D
	base.add_child(sled)
	sled.set_physics_process(false)
	await process_frame
	var sled_position := deep + Vector3(12, 0, 0)
	sled_position.y = terrain.data.get_height(sled_position) + 0.6
	sled.global_position = sled_position
	sled.reset_physics_interpolation()
	for frame in 65:
		await physics_frame
		sled.velocity = Vector3(0, -4, -4 if frame > 30 else 0)
		sled.move_and_slide()
		sled.call("_align_visual_to_ground", 1.0 / 60.0)
	var vehicle_contacts := 0
	for marker: Marker3D in sled.call("get_snow_contact_markers"):
		var behind := marker.global_position + Vector3.BACK * 0.34
		var sample := Vector2(behind.x, behind.z)
		var key := Vector2i((sample / SnowDeformation.TILE_METRES).floor())
		var slot: int = snow._keys.find(key)
		if slot >= 0:
			var cell := Vector2i((sample - Vector2(key) * SnowDeformation.TILE_METRES) / SnowDeformation.PIXEL_SIZE)
			if snow._atlas.get_pixelv(snow._atlas_origin(slot) + cell).r > 0.4:
				vehicle_contacts += 1
	check(vehicle_contacts == 3, "grounded snowmobile deforms snow below both skis and the tread")
	print("SNOWMOBILE floor=", sled.is_on_floor(), " position=", sled.global_position, " compressed contacts=", vehicle_contacts)
	sled.queue_free()
	# Traverse the complete protected arrival-to-entry corridor under normal input.
	var start:=Vector3(-94,0,95);start.y=terrain.data.get_height(start)+0.1
	actor.teleport_authoritative(start,0)
	var reached:=true
	for segment in range(11, -1, -1):
		var t := segment / 12.0
		var x := lerpf(-38.8, -94.0, t) - sin(t * TAU) * 7.5 + sin(t * TAU * 2.0) * 2.1
		var target := Vector3(x, 0.0, lerpf(3.0, 95.0, t))
		for frame in 650:
			var delta:=target-actor.global_position;delta.y=0
			if delta.length()<0.6:break
			actor._input_yaw=atan2(-delta.x,-delta.z)
			hold_forward()
			await physics_frame
		Input.action_release("move_forward")
		var remaining:Vector3=target-actor.global_position;remaining.y=0
		reached=reached and remaining.length()<0.8
		print("APPROACH waypoint=",target," actual=",actor.global_position)
	check(reached,"normal walking traverses the full arrival-to-base corridor without jumping")
	actor.set_physics_process(false)
	exterior.get_node("Blizzard").enabled=false
	actor.get_node("PlayerUI/CameraPostProcess").effect_enabled=false
	actor.head.look_at(Vector3(-57,terrain.data.get_height(Vector3(-57,0,18)),18))
	await shot("normal-walk-bootprints")
	at=Vector3(-92,0,95);at.y=terrain.data.get_height(at)+.1
	actor.teleport_authoritative(at,0)
	actor.head.look_at(Vector3(-20,1.2,0))
	await shot("base-rise-arrival-clear")
	at=Vector3(-62,0,21);at.y=terrain.data.get_height(at)+0.1
	actor.teleport_authoritative(at,0)
	actor.head.look_at(Vector3(-43,1.1,3))
	await shot("sculpted-snow-clear")
	if "--benchmark" in OS.get_cmdline_user_args():
		menu.get_node("GraphicsQuality").set_process(false)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps=0
		var timings:Array=[]
		for repeat in 3:
			for enabled in [false,true]:
				terrain.material.set_shader_param("entry_snow_enabled",enabled)
				for frame in 40:await process_frame
				var started=Time.get_ticks_usec()
				for frame in 120:await process_frame
				var ms=(Time.get_ticks_usec()-started)/120000.0
				timings.append({"sample":repeat,"new_material":enabled,"frame_ms":ms})
				print("SNOW BENCH ",timings[-1])
		FileAccess.open(output+"snow-frame-times.json",FileAccess.WRITE).store_string(JSON.stringify(timings,"  "))
		terrain.material.set_shader_param("entry_snow_enabled",true)
		Engine.max_fps=60
	exterior.get_node("Blizzard").enabled=true
	actor.get_node("PlayerUI/CameraPostProcess").effect_enabled=true
	await shot("sculpted-snow-storm")
	# Let gameplay nodes and render resources leave the tree before shutting down.
	actor=null;current_scene=null;session.queue_free()
	for frame in 8:await process_frame
	await RenderingServer.frame_post_draw
	print("SNOW SESSION CHECKS ",checks," FAILURES ",failures)
	quit(1 if failures else 0)
