extends SceneTree
## Offline Terrain3D edit: clear the old slot and remove terrain crossing the
## new rock opening. Changes control holes only, never the friend's height map.
func _initialize():run.call_deferred()
func run():
	root.get_node("GameMenu/GraphicsQuality").set_process(false)
	var snow=load("res://scenes/levels/snow_exterior.tscn").instantiate();snow.set_script(null);root.add_child(snow)
	for frame in 4:await process_frame
	var data=snow.get_node("Terrain3D").data
	for x in range(324,347):
		for z in range(-4,9):data.set_control_hole(Vector3(x,0,z),true)
	data.update_maps();data.save_directory("res://assets/environments/snow/expanded_terrain")
	print("MOUTH_TERRAIN_FIT control holes X324..346 Z-4..8; all heights preserved")
	quit()
