extends SceneTree
## Real models, native audio playback/capture, physical occlusion and animation clocks.
var checks := 0
var failures := 0
var world: Node3D
var camera: Camera3D
var actor: CharacterBody3D
var sound: AudioStreamPlayer3D
var wall: StaticBody3D
var capture: AudioEffectCapture
var effects_bus := -1
var heard: Array[StringName] = []
var contacts: Array[float] = []
var capture_directory := ""

func _initialize() -> void:
	var isolated := "user://monster_sound_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(isolated))
	ProjectSettings.set_setting("northern_lab/testing/settings_path",isolated+"/settings.json")
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)

func frames(count := 3) -> void:
	for i in count: await physics_frame

func box(point: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new(); shape.size = size
	collision.shape = shape; body.add_child(collision)
	world.add_child(body); body.global_position = point
	return body

func spawn(kind: String) -> CharacterBody3D:
	var creature = load("res://scenes/characters/monsters/"+kind+".tscn").instantiate()
	world.add_child(creature)
	creature.set_physics_process(false)
	creature.global_position = Vector3(0,.02,0)
	creature.get_node("MonsterAudio").countdown = 1000.0
	return creature

func record_cue() -> Dictionary:
	sound._cue.stop(); sound._cue_muffled.stop()
	capture.clear_buffer()
	actor.attack_started.emit(null,.5)
	await create_timer(.65).timeout
	var data := capture.get_buffer(capture.get_frames_available())
	var power := Vector2.ZERO
	var peak := 0.0
	var variation := 0.0
	var previous := Vector2.ZERO
	for sample in data:
		power += sample*sample
		variation += (sample-previous).length_squared()
		previous = sample
		peak = maxf(peak,maxf(absf(sample.x),absf(sample.y)))
	return {"rms":sqrt((power.x+power.y)/maxi(1,data.size()*2)),"left":sqrt(power.x/maxi(1,data.size())),"right":sqrt(power.y/maxi(1,data.size())),"peak":peak,"frames":data.size(),"roughness":sqrt(variation/maxf(power.x+power.y,.0000001)),"samples":data}

func save_capture(name: String, data: PackedVector2Array) -> void:
	if capture_directory.is_empty(): return
	DirAccess.make_dir_recursive_absolute(capture_directory)
	var bytes := PackedByteArray(); bytes.resize(data.size()*4)
	for i in data.size():
		bytes.encode_s16(i*4,roundi(clampf(data[i].x,-1.0,1.0)*32767))
		bytes.encode_s16(i*4+2,roundi(clampf(data[i].y,-1.0,1.0)*32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS; wav.stereo = true
	wav.mix_rate = int(AudioServer.get_mix_rate()); wav.data = bytes
	wav.save_to_wav(capture_directory.path_join(name+".wav"))

func walk_contacts(speed: float, duration: float) -> int:
	contacts.clear()
	sound.countdown = 1000.0
	actor.global_position = Vector3(-3,.02,0)
	actor._moving = true
	actor.visual.motion_state = ""
	actor.visual.animate(.016,true,false,false,.5,speed)
	await frames(2)
	capture.clear_buffer()
	var count := roundi(duration*Engine.physics_ticks_per_second)
	for frame in count:
		actor.position.x += speed/Engine.physics_ticks_per_second
		await physics_frame
	var kind := "head_run" if speed > 4 else "head_walk" if actor.model_id == "head" else "evolution_walk"
	save_capture(kind,capture.get_buffer(capture.get_frames_available()))
	return contacts.size()

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): capture_directory = argument.trim_prefix("--output=")
	Engine.max_fps = 60
	world = Node3D.new(); root.add_child(world); current_scene = world
	box(Vector3(0,-.5,0),Vector3(30,1,30))
	wall = box(Vector3(0,2,2),Vector3(5,4,.25))
	wall.get_child(0).disabled = true
	camera = Camera3D.new(); world.add_child(camera)
	camera.global_position = Vector3(0,1.2,4); camera.look_at(Vector3(0,.6,0)); camera.make_current()
	actor = spawn("head")
	sound = actor.get_node("MonsterAudio")
	sound.sound_played.connect(func(kind,_sequence): heard.append(kind))
	sound.footstep_played.connect(func(_surface,phase): contacts.append(phase))
	effects_bus = AudioServer.get_bus_index("Effects")
	AudioServer.set_bus_mute(effects_bus,false)
	capture = AudioEffectCapture.new(); capture.buffer_length = 3.0
	AudioServer.add_bus_effect(effects_bus,capture)
	await frames(8)
	check(sound.profile != null and sound._cue.bus == &"Effects" and sound._cue_muffled.bus == &"MonsterMuffled","authored profile uses existing effects controls and separate muffled send")
	check(AudioServer.get_bus_send(AudioServer.get_bus_index("MonsterMuffled")) == &"Effects","muffled creatures respect Effects volume and World reverb")
	check((sound._feet.stream as AudioStreamPolyphonic).polyphony == 4,"movement voices have bounded native polyphony")
	var direct := await record_cue()
	save_capture("clear_windup",direct.samples)
	direct.erase("samples")
	print("AUDIO DIRECT ",direct)
	check(direct.frames > 1000 and direct.rms > .00001 and direct.peak < .95,"native mixer produces a finite unclipped spatial cue")
	check(heard.count(&"windup") == 1,"real attack signal produces one windup cue")
	wall.get_child(0).disabled = false
	await frames(32)
	var blocked := await record_cue()
	save_capture("muffled_windup",blocked.samples)
	blocked.erase("samples")
	print("AUDIO WALL ",blocked)
	check(sound.occlusion_blend > .95 and blocked.rms < direct.rms*.55,"wall attenuates actual recorded output rather than only changing a flag")
	check(blocked.roughness < direct.roughness*.9,"wall low-pass changes recorded spectral content, not just loudness")
	var probes_before: int = sound.occlusion_probes
	await create_timer(1.0).timeout
	check(sound.occlusion_probes-probes_before <= 7,"occlusion ray probes are throttled, not issued every frame")
	wall.get_child(0).disabled = true
	await frames(35)
	var reopened := await record_cue()
	check(sound.occlusion_blend < .05 and reopened.rms > blocked.rms*1.8,"opening the physical passage restores clear playback")
	var other := spawn("head")
	var other_sound = other.get_node("MonsterAudio")
	actor.global_position = Vector3(-6,.02,0)
	wall.get_child(0).disabled = false
	await frames(40)
	check(sound.occlusion_blend < .05 and other_sound.occlusion_blend > .95,
		"shared profiles keep per-creature acoustic state independent")
	other.queue_free(); actor.global_position = Vector3(0,.02,0)
	wall.get_child(0).disabled = true
	var floor_block := box(Vector3(0,5.5,0),Vector3(20,.5,20))
	camera.global_position = Vector3(0,10,2); camera.look_at(Vector3(0,.6,0))
	await frames(20)
	var another_floor := await record_cue()
	check(sound.floor_blend > .95 and another_floor.rms < direct.rms*.04,"solid floor strongly suppresses another level's monster")
	floor_block.queue_free()
	camera.global_position = Vector3(-3,1.2,4); camera.look_at(Vector3(-3,.6,0))
	actor.global_position = Vector3(-6,.02,0)
	await frames(25)
	var left := await record_cue()
	actor.global_position = Vector3(0,.02,0)
	await frames(25)
	var right := await record_cue()
	check(left.left > left.right*1.05 and right.right > right.left*1.05,"native stereo panning distinguishes left and right threats")
	AudioServer.set_bus_mute(effects_bus,true)
	# Capture after Effects' fader: effects attached on that bus itself are pre-fader.
	var output_capture := AudioEffectCapture.new(); output_capture.buffer_length = 2.0
	var output_bus := AudioServer.get_bus_index("World")
	AudioServer.add_bus_effect(output_bus,output_capture)
	await frames(5)
	output_capture.clear_buffer()
	await record_cue()
	var muted_power := 0.0
	var muted_data := output_capture.get_buffer(output_capture.get_frames_available())
	for sample in muted_data: muted_power += sample.length_squared()
	check(sqrt(muted_power/maxi(1,muted_data.size()*2)) < .000001,"Effects mute also silences occluded monster send")
	AudioServer.remove_bus_effect(output_bus,AudioServer.get_bus_effect_count(output_bus)-1)
	AudioServer.set_bus_mute(effects_bus,false)
	camera.global_position = Vector3(0,1.2,4); camera.look_at(Vector3(0,.6,0))
	actor.global_position = Vector3(0,.02,0)
	await frames(20)
	heard.clear()
	actor.target_spotted.emit(null); actor.target_spotted.emit(null)
	await frames(3)
	check(heard.count(&"alert") == 1,"repeated reacquisition is debounced")
	actor.target_lost.emit(Vector3.ZERO)
	await frames(8)
	actor.target_spotted.emit(null)
	await create_timer(.8).timeout
	check(not heard.has(&"search"),"brief sight flicker cannot produce a false lost-target cue")
	actor._sees_target = false
	actor.target_lost.emit(Vector3.ZERO)
	await create_timer(.9).timeout
	check(heard.count(&"search") == 1,"confirmed target loss has its own single cue")
	actor._windup = .5
	actor.attack_started.emit(null,.5)
	await frames(3)
	actor._cancel_attack()
	await frames(3)
	check(not sound._cue.playing and not heard.has(&"miss"),"cancelled attack stops its warning without inventing a miss/impact")
	actor.attack_started.emit(null,.5); await frames(3)
	actor.attack_finished.emit(null,true); await frames(3)
	check(heard.has(&"strike"),"successful contact selects strike sound")
	actor.attack_finished.emit(null,false); await frames(3)
	check(heard.has(&"miss"),"completed missed strike has a different cue")
	await create_timer(.3).timeout
	var normal := await walk_contacts(actor.visual.walk_reference_speed,1.0)
	var fast := await walk_contacts(5.2,1.0)
	print("HEAD CONTACTS normal=",normal," fast=",fast)
	check(normal >= 5 and fast > normal*1.5,"head contacts accelerate with native gait playback")
	var close_to_contact := true
	for phase in contacts:
		var error := minf(minf(phase,1.0-phase),absf(phase-.5))
		if error > .16: close_to_contact = false
	check(close_to_contact,"head sounds occur near authored paired foot plants")
	contacts.clear()
	actor._moving = true
	await frames(20)
	check(contacts.is_empty(),"walking animation on an unmoving actor cannot generate footsteps")
	actor.global_position += Vector3(4,0,0); await frames()
	check(contacts.is_empty(),"teleport cannot generate a burst of footsteps")
	var before := heard.size()
	actor.visible = false; actor.target_spotted.emit(null); await frames()
	check(not sound.playing and not sound._feet.playing and not sound._cue.playing and heard.size()==before,"hidden/resolved content remains silent")
	actor.visible = true; actor.health = 0.0; actor.attack_started.emit(null,.5); await frames()
	check(not sound.playing and not sound._cue.playing,"dead creature cannot produce live warning cues")
	actor.queue_free(); await frames()
	actor = spawn("involuntary_evolution"); sound = actor.get_node("MonsterAudio")
	sound.footstep_played.connect(func(_surface,phase): contacts.append(phase))
	var heavy := await walk_contacts(actor.visual.walk_reference_speed,1.9)
	check(heavy >= 5 and heavy <= 8,"three-legged evolution uses three contacts per native cycle")
	check(sound.profile.step_volume_db > -20 and sound.profile.floor_steps[0].get_length() > .1,"evolution has heavier, longer contacts than the head")
	var idle_probes: int = sound.occlusion_probes
	camera.global_position = Vector3(0,2,100)
	await frames(40)
	check(sound.occlusion_probes <= idle_probes+1 and not sound.playing,"far creatures stop voices and acoustic ray work")
	AudioServer.remove_bus_effect(effects_bus,AudioServer.get_bus_effect_count(effects_bus)-1)
	world.queue_free(); await frames(6)
	print("MONSTER AUDIO CHECKS ",checks," FAILURES ",failures)
	quit(1 if failures else 0)
