extends SceneTree
var checks:=0
var failures:=0
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func settle(frames:=5) -> void:
	for frame in frames:await physics_frame
func run() -> void:
	root.get_node("GameMenu").force_close_menu()
	AudioServer.set_bus_mute(0,true)
	var arena=load("res://tools/tests/fixtures/character_test_arena.tscn").instantiate()
	root.add_child(arena)
	var witness=Node3D.new()
	witness.set_script(load("res://tools/tests/fixtures/heavy_audio_noise_witness.gd"))
	arena.add_child(witness)
	for kind in ["bench","sofa","concrete_joist_1","concrete_joist_2"]:
		var prop:HeavyCarryProp=load("res://scenes/objects/props/"+kind+".tscn").instantiate()
		arena.add_child(prop)
		prop.freeze=true
		prop.set_physics_process(false)
		var sound=prop.get_node("CarryAudio")
		sound.set_process(false)
		check(sound.drag.stream is AudioStreamWAV and sound.drag.stream.loop_mode==AudioStreamWAV.LOOP_FORWARD,"native continuous loop: "+kind)
		check(sound.lift_stream!=null and sound.place_stream!=null,"separate lift/place clips: "+kind)
		check(sound.drag.bus==&"Effects" and sound.event.max_distance>0,"spatial effects bus: "+kind)
		var before:int=witness.heard.size()
		sound.observe_contacts(true,true,0,4,0,.016)
		check(not sound.event.playing and witness.heard.size()==before,"initial settling stays silent: "+kind)
		sound._age=1
		sound.observe_contacts(true,true,0,0,0,.2)
		sound._process(.2)
		check(not sound.drag.playing and witness.heard.size()==before,"stationary grounded prop is silent: "+kind)
		sound.observe_contacts(true,true,.45,0,0,.2)
		sound._process(.1)
		check(sound.drag.playing and sound.drag.volume_db<=sound.drag_volume_db,"motion controls audible loop and bounded gain: "+kind)
		check(witness.heard.size()==before+1 and witness.heard.back().source==prop,"host physics emits positional AI noise: "+kind)
		prop.grips={1:{},2:{}}
		sound.observe_contacts(false,false,2,0,.5,.2)
		sound._process(.2)
		check(not sound.drag.playing,"airborne moving prop does not scrape: "+kind)
		check(sound.event.playing and sound.event.stream==sound.lift_stream,"real ground departure plays lift: "+kind)
		prop.grips.clear()
		sound.observe_contacts(true,true,0,2.8,-1,.2)
		check(sound.event.stream==sound.place_stream and sound._impact_cooldown>0,"contact impact plays placement: "+kind)
		var after:int=witness.heard.size()
		for repeat in 10:sound.observe_contacts(true,true,0,2.8,0,.016)
		check(witness.heard.size()==after,"impact cooldown prevents repeated contact spam: "+kind)
		sound._receive_motion(.6)
		sound._process(.1)
		sound._last_received=-1000
		sound._process(.2)
		check(not sound.drag.playing,"lost stop packets cannot leave a loop: "+kind)
		prop.queue_free()
		await settle()
	# Verify the engine contact path, not just the contact-state handler.
	var real:HeavyCarryProp=load("res://scenes/objects/props/bench.tscn").instantiate()
	arena.add_child(real)
	real.get_node("CarryAudio").set_process(false)
	await settle(40)
	var sound=real.get_node("CarryAudio")
	real.position.y=1.2
	real.sleeping=false
	var impacted:=false
	for frame in 80:
		await physics_frame
		if sound._impact_cooldown>0:impacted=true;break
	check(impacted,"actual Jolt contact impulse triggers a placement sound")
	var scraped:=false
	for frame in 35:
		real.linear_velocity=Vector3(.8,0,0)
		real.sleeping=false
		await physics_frame
		if sound._target_speed>.08:scraped=true
	check(scraped,"actual ground friction drives the replicated scraping state")
	arena.queue_free()
	await settle()
	print("HEAVY AUDIO CHECKS ",checks," FAILURES ",failures)
	quit(1 if failures else 0)
