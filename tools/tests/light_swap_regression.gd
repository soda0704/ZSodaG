extends SceneTree
## Regression for removing /light_swap: independent effects, loading and persistence.
var checks := 0
var failures := 0
var restart_settings := ""
func _initialize():
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--restart-settings="): restart_settings=arg.trim_prefix("--restart-settings=")
	var prefix := "user://independent_lighting_%d" % OS.get_process_id()
	ProjectSettings.set_setting("northern_lab/testing/settings_path",prefix+".json" if restart_settings.is_empty() else restart_settings)
	ProjectSettings.set_setting("northern_lab/testing/controls_path",prefix+".cfg")
	create_timer(100).timeout.connect(func():quit(2));run.call_deferred()
func check(ok: bool, label: String):
	checks+=1
	if not ok: failures+=1
	print("PASS " if ok else "FAIL ",label)
func settle():
	for frame in 8: await process_frame
func run():
	await process_frame
	var menu=root.get_node("GameMenu")
	var quality=menu.get_node("GraphicsQuality")
	quality.set_process(false)
	if not restart_settings.is_empty():
		check(quality.values.GIQuality==0 and quality.values.AOQuality==3 and quality.values.Bloom and quality.values.ShadowQuality==3,"a new process restores the saved mixed choices without a hidden mode reset")
		print("INDEPENDENT LIGHTING RESTART CHECKS ",checks," FAILURES ",failures);quit(1 if failures else 0);return
	var console=root.get_node("DeveloperConsole")
	check(not console._all_commands().any(func(command):return str(command).begins_with("/light_swap")),"obsolete lighting command is absent from help and completion")
	check(not quality.has_method("set_advanced_lighting_enabled"),"no combined runtime override remains")
	var world:=Node3D.new();root.add_child(world)
	var node:=WorldEnvironment.new();node.environment=Environment.new()
	node.environment.ssao_enabled=true;node.environment.glow_enabled=true;node.environment.volumetric_fog_enabled=true
	node.environment.ambient_light_energy=.025;world.add_child(node)
	var camera:=Camera3D.new();world.add_child(camera);camera.current=true
	var gi=load("res://scenes/levels/world_indirect_lighting.tscn").instantiate();world.add_child(gi);gi.set_process(false)
	var isolation=load("res://scenes/levels/interior_ambient_occlusion.tscn").instantiate();world.add_child(isolation)
	var lights:=Node3D.new();lights.name="WorldLighting";world.add_child(lights)
	for name in ["Standard","Emergency"]:
		var group:=Node3D.new();group.name=name;lights.add_child(group)
	var lamp:=OmniLight3D.new();lamp.light_energy=3;lamp.light_color=Color(.8,.9,1);lamp.shadow_enabled=true;lights.get_node("Standard").add_child(lamp)
	var power:=BasePowerLightingController.new();power.name="BasePowerLightingController";world.add_child(power);power.apply_power_state(true,true)
	quality.apply({"GIQuality":2,"AOQuality":3,"Bloom":true,"FogQuality":3,"ShadowQuality":3})
	await settle();gi.update_floor(3)
	check(gi.get_active_probe_count()>0 and camera.environment.ssao_enabled and camera.environment.glow_enabled,"GI and authored effects start active at their selected qualities")
	quality.set_gi_quality(0);await settle();gi.update_floor(3)
	check(gi.get_active_probe_count()==0 and gi.get_children().all(func(probe):return probe.data==null),"GI Off releases volume data")
	check(camera.environment.ssao_enabled and camera.environment.glow_enabled and camera.environment.volumetric_fog_enabled and root.positional_shadow_atlas_size==4096,"GI Off preserves SSAO, Glow, fog and shadow quality")
	check(is_equal_approx(lamp.light_energy,3) and lamp.shadow_enabled and power.is_standard_powered,"GI quality preserves direct sources and power")
	check(isolation.get_node("Fallback").get_children().all(func(probe):return probe.ambient_mode==ReflectionProbe.AMBIENT_COLOR),"GI Off retains interior sky isolation")
	quality.set_gi_quality(1);await settle();gi.update_floor(3)
	check(gi.get_active_probe_count()>0,"GI Low restores the actual nearby volumes")
	var chosen:Dictionary=quality.values.duplicate();chosen.AOQuality=0;quality.apply(chosen);await settle()
	check(not camera.environment.ssao_enabled and camera.environment.glow_enabled and gi.get_active_probe_count()>0,"SSAO Off only disables SSAO")
	chosen=quality.values.duplicate();chosen.Bloom=false;chosen.AOQuality=2;quality.apply(chosen);await settle()
	check(camera.environment.ssao_enabled and not camera.environment.glow_enabled and gi.get_active_probe_count()>0,"Glow Off preserves SSAO and GI")
	chosen=quality.values.duplicate();chosen.ShadowQuality=1;quality.apply(chosen);await settle()
	check(root.positional_shadow_atlas_size==2048 and camera.environment.ssao_enabled and gi.get_active_probe_count()>0,"Low shadows change the atlas without disabling other effects")
	check(node.environment.ssao_enabled and node.environment.glow_enabled and is_equal_approx(node.environment.ambient_light_energy,.025),"quality never overwrites the authored Environment resource")
	power.apply_power_state(false);await settle();gi.update_floor(3)
	check(gi.get_active_probe_count()==0 and not lights.get_node("Standard").visible and lights.get_node("Emergency").visible,"an outage selects the real backup circuit without neutral GI")
	quality.set_gi_quality(3);await settle();gi.update_floor(3)
	check(gi.get_active_probe_count()==0 and quality.values.GIQuality==3,"requesting High GI cannot bypass a power outage")
	power.apply_power_state(true);await settle();gi.update_floor(3)
	check(gi.get_active_probe_count()>0 and quality.values.GIQuality==3,"power restoration honours the retained GI choice")
	quality.set_gi_quality(0);power.apply_power_state(false);power.apply_power_state(true);await settle();gi.update_floor(3)
	check(gi.get_active_probe_count()==0,"power restoration never overrides an explicit GI Off choice")
	quality.set_gi_quality(2);gi.set_debug_disabled(true);gi.update_floor(3)
	check(gi.get_active_probe_count()==0,"fullbright can independently suppress GI")
	quality.set_gi_quality(0);quality.set_gi_quality(2);gi.update_floor(3)
	check(gi.get_active_probe_count()==0,"changing GI does not cancel fullbright")
	gi.set_debug_disabled(false);gi.update_floor(3)
	check(gi.get_active_probe_count()>0,"GI returns after ending the debug override")
	gi.prepare_loading();quality.set_gi_quality(0);await gi.finish_loading(3)
	check(gi.get_active_probe_count()==0 and gi.get_children().all(func(probe):return probe.data==null),"arrival loading cannot reactivate disabled GI")
	var late=load("res://scenes/levels/world_indirect_lighting.tscn").instantiate();world.add_child(late);await settle();late.update_floor(3)
	check(late.get_active_probe_count()==0 and not late._quality_enabled,"late-loaded volumes inherit GI Off")
	quality.apply({"GIQuality":0,"AOQuality":3,"Bloom":true,"ShadowQuality":3})
	menu._settings_data.Graphics=quality.values.duplicate();menu._settings_data.GraphicsCalibrationPending=false
	check(menu.save_settings_data(),"independent graphics choices are saved through GameMenu")
	var saved:Dictionary=menu.load_settings_data().Graphics
	check(saved==quality.values and saved.GIQuality==0,"saved GI Off and mixed choices round-trip without a mode flag")
	# Exercise the real Settings controls, including the previously missing Off choice.
	menu.open_settings();await create_timer(1.2).timeout
	var panel=menu.settings_panel;panel.select_category(1);await process_frame
	var option:OptionButton=panel.rows.find_child("GIQuality",true,false)
	check(option.item_count==4 and option.selected==0,"GI menu exposes Off and displays the saved selection")
	check(panel.rows.find_child("FogQuality",true,false)==null and panel.rows.find_child("VegetationDistance",true,false)==null,"unavailable terrain and volume controls are absent")
	option.select(2);option.item_selected.emit(2)
	check(panel.draft.Graphics.GIQuality==2 and quality.values.GIQuality==0,"GI edits remain staged until Apply")
	check(panel.apply(false) and quality.values.GIQuality==2 and not panel.has_changes(),"Apply updates the real GI setting and clears pending edits")
	panel.draft.GraphicsCalibrationPending=true;panel.reset_category()
	check(not panel.draft.GraphicsCalibrationPending,"resetting quality cancels the pending automatic recommendation")
	menu.force_close_menu()
	quality.apply({"GIQuality":0,"AOQuality":3,"Bloom":true,"ShadowQuality":3})
	menu._settings_data.Graphics=quality.values.duplicate();menu._settings_data.GraphicsCalibrationPending=false;menu.save_settings_data()
	if OS.get_environment("NORTHERNLAB_EXPORT_CAPTURE_DIR").is_empty():
		var output:Array=[]
		var code:=OS.execute(OS.get_executable_path(),PackedStringArray(["--headless","--path",ProjectSettings.globalize_path("res://"),"--script","res://tools/tests/light_swap_regression.gd","--","--restart-settings="+menu.get_settings_path()]),output,true)
		for line in output:print(line)
		check(code==0,"independent choices survive an actual process restart")
	world.queue_free();await process_frame
	print("INDEPENDENT LIGHTING CHECKS ",checks," FAILURES ",failures);quit(1 if failures else 0)
