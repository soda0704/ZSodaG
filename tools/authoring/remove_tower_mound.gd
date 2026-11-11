extends SceneTree
const BACKUP:="res://tools/.local/tower-flat-2026-11-11/"
func _initialize():run.call_deferred()
func run():
	if DirAccess.dir_exists_absolute(BACKUP):push_error("Tower mound already removed");quit(1);return
	DirAccess.make_dir_recursive_absolute(BACKUP)
	var dir:="res://assets/environments/snow/expanded_terrain/"
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".res"):DirAccess.copy_absolute(dir+f,BACKUP+f)
	var path:="res://scenes/levels/snow_exterior.tscn";DirAccess.copy_absolute(path,BACKUP+"snow_exterior.tscn")
	var snow=load(path).instantiate();snow.set_script(null)
	for child in snow.find_children("*","",true,false):
		if child.get_script()!=null:child.set_script(null)
	root.add_child(snow);var data=snow.get_node("Terrain3D").data
	var centre:=Vector3(0,0,-180);var old:float=data.get_height(centre)
	var west:float=data.get_height(centre+Vector3(-48,0,0));var east:float=data.get_height(centre+Vector3(48,0,0))
	var north:float=data.get_height(centre+Vector3(0,0,-48));var south:float=data.get_height(centre+Vector3(0,0,48))
	var level:float=(west+east+north+south)*.25;var count:=0
	for x in range(-49,50):
		for z in range(-229,-130):
			var at:=Vector3(x,0,z);var radius:=Vector2(x,z+180).length()
			if radius>=48:continue
			var before:float=data.get_height(at)
			var plane:=level+(east-west)*x/96+(south-north)*(z+180)/96
			var target:=lerpf(plane,before,smoothstep(14,48,radius))
			if absf(target-before)>.001:data.set_height(at,target);count+=1
	data.update_maps();data.save_directory(dir)
	var tower:Node3D=snow.get_node("RadioTower");var next_y:=tower.position.y+level-old
	var text:=FileAccess.get_file_as_string(path)
	var source:="transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 10.2, -180)"
	assert(text.contains(source))
	text=text.replace(source,"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, %.6f, -180)"%next_y)
	FileAccess.open(path,FileAccess.WRITE).store_string(text)
	print("PASS tower mound removed samples=",count," old ground=",old," new ground=",level," tower root=",next_y)
	snow.free();quit()
