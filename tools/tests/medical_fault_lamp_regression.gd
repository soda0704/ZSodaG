extends SceneTree
## Actual room, power controller, bounded lighting pool and native looping audio.
var checks := 0
var failures := 0

func _initialize() -> void:
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, "user://medical_lamp_%d.cfg" % OS.get_process_id())
	ProjectSettings.set_setting("northern_lab/testing/settings_path", "user://medical_lamp_%d.json" % OS.get_process_id())
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func frames(count := 4) -> void:
	for i in count: await process_frame

func run() -> void:
	Engine.max_fps = 60
	var level: Node3D = load("res://scenes/levels/base_blockout_v03.tscn").instantiate()
	level.network_runtime_managed = true
	root.add_child(level); current_scene = level
	var state: BaseGameplayController = level.get_node("BaseGameplayController")
	state.progress_persistence_enabled = false; state.set_process(false)
	state.containment = {"fault":false}
	var lighting: WorldLighting = level.get_node("WorldLighting")
	lighting.set_process(false)
	var power: BasePowerLightingController = level.get_node("BasePowerLightingController")
	var lamp: AudioStreamPlayer3D = lighting.get_node("MedicalFaultLamp")
	var camera := Camera3D.new(); level.add_child(camera)
	camera.position = Vector3(24,1.7,5.5); camera.make_current()
	await frames()
	check(lamp._lamp == lighting.get_node("Standard/Medical1") and lamp._power == power, "fault belongs to the primary medical lamp and actual lighting circuit")
	check(lamp._material != null and lamp._material.resource_path.is_empty(), "existing fixture uses an isolated lens material")
	check(lamp.bus == &"Machinery" and lamp.max_distance == 13.0 and lamp.running_volume_db <= -12.0, "quiet positional source uses existing machinery controls and bounded range")
	var stream := lamp.stream as AudioStreamWAV
	var clip: Animation = lamp._animation.get_animation(&"fault")
	check(stream != null and stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "native audio stream loops forward without restarting from script")
	check(absf(stream.get_length()-clip.length) < .0001 and clip.loop_mode == Animation.LOOP_LINEAR, "native flicker animation and recording have matching loop periods")
	var data := stream.data
	var seam := absf(float(data.decode_s16(0)-data.decode_s16(data.size()-2))/32768.0)
	check(seam < .0002, "edited PCM seam has no abrupt amplitude jump")
	check(not lamp.playing and lamp.intensity == 0 and lamp._material.emission_energy_multiplier == 0, "unpowered room starts with a silent dark faulty fixture")
	power.apply_power_state(true)
	await create_timer(.25).timeout
	check(lamp.playing and lamp.volume_db >= -12.1, "restored power starts the authored recording with a short fade")
	lamp.set_process(false)
	var bright_time := 0.0; var dark_time := 0.0
	var bright := 0.0; var dark := 1.0
	for key in clip.track_get_key_count(0):
		var value: float = clip.track_get_key_value(0,key)
		if value > bright: bright = value; bright_time = clip.track_get_key_time(0,key)
		if value < dark: dark = value; dark_time = clip.track_get_key_time(0,key)
	check(bright > .98 and dark < .15, "recording has both steady light and substantial authored contact failures")
	for step in 20: lighting._update_lamps(camera.position,.05)
	var stable: Light3D = lighting.get_node("Standard/Medical2")
	var stable_energy := stable.light_energy
	lamp._animation.seek(bright_time,true)
	lighting._update_lamps(camera.position,.05)
	var full_energy: float = lamp._lamp.light_energy
	lamp._animation.seek(dark_time,true)
	lighting._update_lamps(camera.position,.05)
	check(full_energy > .5 and lamp._lamp.light_energy < full_energy*.16, "fault multiplier survives normal light-pool updates")
	check(is_equal_approx(lamp._material.emission_energy_multiplier,lamp.emission_energy*lamp.intensity), "visible lens dims with the same contact failure as room illumination")
	check(is_equal_approx(stable.light_energy,stable_energy), "second medical source is unaffected")
	check(lighting._resident_lamps.size() <= WorldLighting.MAX_RESIDENT_LAMPS, "flicker does not allocate lights or bypass atlas residency budget")
	var capture := AudioEffectCapture.new()
	var bus := AudioServer.get_bus_index("Machinery")
	AudioServer.add_bus_effect(bus,capture)
	lamp.set_process(true)
	await create_timer(.4).timeout
	var samples := capture.get_buffer(capture.get_frames_available())
	var peak := 0.0; var energy := 0.0
	for sample in samples:
		peak = maxf(peak,maxf(absf(sample.x),absf(sample.y)))
		energy += sample.length_squared()
	var rms := sqrt(energy / maxi(1,samples.size()*2))
	print("MEDICAL AUDIO RMS ",rms," PEAK ",peak)
	check(is_finite(rms) and rms > .0001 and peak < .35, "native listener receives an audible bounded electrical sound")
	lamp.play(stream.get_length()-.12)
	await create_timer(.4).timeout
	check(lamp.playing and lamp.get_playback_position() < 1.0, "native playback crosses the edited loop without stopping")
	var clock := fposmod(maxf(0.0,lamp.get_playback_position()+AudioServer.get_time_since_last_mix()-AudioServer.get_output_latency()),stream.get_length())
	var difference := absf(lamp._animation.current_animation_position-clock)
	check(minf(difference,stream.get_length()-difference) < .06, "flicker follows audible playback position across the loop seam")
	state.main_breaker_on = true
	state.containment["fault"] = true
	state.snapshot_changed.emit(state.get_snapshot())
	await create_timer(.2).timeout
	check(not power.is_standard_powered and not lamp.playing and lamp.intensity == 0 and lamp._material.emission_energy_multiplier == 0, "containment outage silences the faulty lamp even with the breaker on")
	state.containment["fault"] = false
	state.snapshot_changed.emit(state.get_snapshot())
	await create_timer(.2).timeout
	check(lamp.playing and lamp.intensity > 0, "restoring circuit after snapshot resumes sound and light")
	power.apply_power_state(false)
	await create_timer(.2).timeout
	check(not lamp.playing and lamp._gain == 0 and lamp.intensity == 0, "normal power loss fades sound out and extinguishes lens")
	power.apply_power_state(true); await frames(1)
	power.apply_power_state(false); await frames(1)
	power.apply_power_state(true); await create_timer(.15).timeout
	check(lamp.playing and is_equal_approx(lamp._gain,1.0), "rapid circuit toggles recover without orphaned animation or sound")
	AudioServer.remove_bus_effect(bus,AudioServer.get_bus_effect_count(bus)-1)
	level.queue_free(); await frames()
	print("MEDICAL FAULT CHECKS ",checks," FAILURES ",failures)
	quit(0 if failures == 0 else 1)
