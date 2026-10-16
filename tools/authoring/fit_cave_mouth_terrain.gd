extends SceneTree
## Offline Terrain3D edit: clear the old slot and remove terrain crossing the
## new rock opening. Changes control holes only, never the friend's height map.
func _initialize():run.call_deferred()
func run():
	root.get_node("GameMenu/GraphicsQuality").set_process(false)
	var camera:=Camera3D.new();root.add_child(camera);camera.current=true
	var snow=load("res://scenes/levels/snow_exterior.tscn").instantiate();snow.set_script(null);root.add_child(snow)
	for frame in 4:await process_frame
	var data=snow.get_node("Terrain3D").data
	for x in range(324,347):
		for z in range(-4,9):data.set_control_hole(Vector3(x,0,z),false)
	for x in range(327,344):
		for z in range(-2,7):data.set_control_hole(Vector3(x,0,z),true)
	data.update_maps();data.save_directory("res://assets/environments/snow/expanded_terrain")
	print("MOUTH_TERRAIN_FIT control holes X327..343 Z-2..6; all heights preserved")
	quit()
