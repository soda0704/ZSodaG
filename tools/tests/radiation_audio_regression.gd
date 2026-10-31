extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void:
	var prefix:="user://radiation_audio_%d"%OS.get_process_id()
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING,prefix+".cfg")
	ProjectSettings.set_setting("northern_lab/testing/settings_path",prefix+".json")
	ProjectSettings.set_setting(JournalReadingStore.ROOT_SETTING,prefix)
	create_timer(65).timeout.connect(func():quit(2))
	run.call_deferred()
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func run() -> void:
	Engine.max_fps=60
	var base:Node3D=load("res://scenes/levels/base_blockout_v03.tscn").instantiate()
	root.add_child(base);current_scene=base
	for frame in 20:await physics_frame
	root.get_node("GameMenu").force_close_menu()
	var actor:GamePlayer=get_first_node_in_group("local_player")
	actor.set_physics_process(false);actor.survival.set_physics_process(false);actor.player_audio.set_process(false)
	base.get_node("BaseGameplayController").set_process(false)
	var zone:RadiationZone=get_first_node_in_group("radiation_zones")
	var safe:=zone.to_global(Vector3(zone.radius+4,1,0))
	var exposed:=zone.to_global(Vector3(0,1,0))
	var audio:AudioStreamPlayer=actor.player_audio.radiation_audio
	actor.teleport_authoritative(safe,0)
	actor.player_audio._process(.1)
	check(not audio.playing,"outside radiation zone does not start the recording")
	check(audio.stream is AudioStreamWAV and audio.stream.loop_mode==AudioStreamWAV.LOOP_FORWARD and audio.stream.get_length()>0,"supplied WAV is decoded and loops throughout sustained exposure")
	actor.teleport_authoritative(exposed,0)
	actor.survival.radiation=0;actor.survival.health=100
	actor.survival._physics_process(.2)
	check(actor.survival.radiation>0 and actor.survival.health==100,"real reservoir grants dose before radiation injury starts")
	actor.player_audio._process(.1)
	var first:=audio.volume_db
	check(audio.playing and first<actor.player_audio.radiation_volume_db-3 and first> -80,"receiving radiation starts the recording quietly")
	actor.player_audio._process(.2)
	check(audio.volume_db>first and audio.volume_db<actor.player_audio.radiation_volume_db,"sound fades towards its configured level")
	for step in 20:actor.player_audio._process(.1)
	check(absf(audio.volume_db-actor.player_audio.radiation_volume_db)<.1,"continuous exposure settles at the configured volume")
	actor.survival.radiation=100
	actor.player_audio._process(.1)
	check(audio.playing,"saturated dose does not silence continuing exposure")
	var peak:=audio.volume_db
	actor.teleport_authoritative(safe,0)
	actor.player_audio._process(.1)
	check(audio.playing and audio.volume_db<peak and audio.volume_db> -80,"leaving the zone fades out instead of cutting off")
	for step in 70:actor.player_audio._process(.1)
	check(not audio.playing and actor.survival.radiation==100,"recording stops outside even while accumulated dose remains high")
	actor.teleport_authoritative(exposed,0);actor.player_audio._process(.1)
	check(audio.playing and audio.volume_db<actor.player_audio.radiation_volume_db-3,"re-entering starts a fresh gentle fade in")
	actor.teleport_authoritative(safe,0);actor.player_audio._process(.1)
	var falling:=audio.volume_db
	actor.teleport_authoritative(exposed,0);actor.player_audio._process(.1)
	check(audio.playing and audio.volume_db>falling,"rapid re-entry reverses the fade smoothly")
	var guest:GamePlayer=load("res://scenes/characters/player.tscn").instantiate()
	guest.name="2";guest.setup(2,"Guest",exposed,Color.WHITE,0,1);base.add_child(guest)
	guest.set_physics_process(false);guest.survival.set_physics_process(false);guest.player_audio.set_process(false)
	guest.player_audio._process(.2)
	check(not guest.player_audio.radiation_audio.playing,"another exposed player never adds a second local Geiger loop")
	actor.survival.dead=true
	for step in 70:actor.player_audio._process(.1)
	check(not audio.playing,"death fades the local radiation sound to silence")
	actor.survival.dead=false;actor.teleport_authoritative(safe,0)
	actor.survival.apply_checkpoint({"health":100,"radiation":70,"dead":false})
	actor.player_audio._process(.2)
	check(not audio.playing,"restoring accumulated dose outside the zone does not start the sound")
	actor=null;current_scene=null;base.queue_free()
	for frame in 6:await process_frame
	print("RADIATION AUDIO CHECKS ",checks," FAILURES ",failures)
	quit(1 if failures else 0)
