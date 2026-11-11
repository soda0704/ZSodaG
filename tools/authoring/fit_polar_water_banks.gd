extends SceneTree
const DIR:="res://assets/environments/snow/expanded_terrain/"
const BACKUP:="res://tools/.local/polar-expansion-2026-11-11/before-bank-fit/"
const POINTS:=[Vector2(-215,-170),Vector2(-205,-145),Vector2(-214,-120),Vector2(-195,-90),Vector2(-204,-65),Vector2(-188,-40)]
func _initialize():run.call_deferred()
func run():
	if DirAccess.dir_exists_absolute(BACKUP):push_error("Bank adjustment already applied");quit(1);return
	DirAccess.make_dir_recursive_absolute(BACKUP)
	for f in DirAccess.get_files_at(DIR):
		if f.ends_with(".res"):DirAccess.copy_absolute(DIR+f,BACKUP+f)
	var layout:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tools/authoring/polar_waterways_layout.json"))
	var ponds:=[Vector4(105,95,32,12),Vector4(-215,90,17,31)]
	var camera:=Camera3D.new();root.add_child(camera);camera.current=true
	var snow=load("res://scenes/levels/snow_exterior.tscn").instantiate()
	# Pure authoring: gameplay scripts must not edit distant regions on ready.
	snow.set_script(null)
	for child in snow.find_children("*","",true,false):
		if child.get_script()!=null:child.set_script(null)
	root.add_child(snow)
	var data=snow.get_node("Terrain3D").data;var count:=0
	for x in range(-260,155):
		for z in range(-210,165):
			var p:=Vector2(x,z);var at:=Vector3(x,0,z);var old:float=data.get_height(at)
			if not is_finite(old) or data.get_control_hole(at):continue
			var h:=old
			for i in 2:
				var basin:Vector4=ponds[i];var q:=(p-Vector2(basin.x,basin.y))/Vector2(basin.z,basin.w);var a:=atan2(q.y,q.x);var r:=q.length()*(1+.12*sin(a*3+i)+.07*sin(a*5))
				h=lerpf(h,maxf(h,float(layout.pond_levels[i])+.35),exp(-pow((r-1.05)/.22,2)))
			var distance:=INF;var level:=0.0;var width:=3.2
			for k in POINTS.size()-1:
				var a:Vector2=POINTS[k];var b:Vector2=POINTS[k+1];var t:=clampf((p-a).dot(b-a)/(b-a).length_squared(),0,1);var d:=p.distance_to(a.lerp(b,t))
				if d<distance:distance=d;level=lerpf(layout.stream_levels[k],layout.stream_levels[k+1],t);width=3.2+1.2*sin((k+t)*1.3)
			h=lerpf(h,maxf(h,level+.3),exp(-pow((distance-width-3)/2.5,2)))
			if h-old>.001:data.set_height(at,h);count+=1
	data.update_maps();data.save_directory(DIR)
	var detail=load("res://scenes/levels/polar_ice_lowland.tscn").instantiate()
	for i in 2:
		var node:MeshInstance3D=detail.get_node("WaterBasin%d"%i);var material:=ShaderMaterial.new();material.shader=load("res://assets/environments/snow/shallow_polar_water.gdshader");material.set_shader_parameter("mask_type",1);material.set_shader_parameter("basin_bounds",ponds[i]);material.set_shader_parameter("basin_phase",float(i));node.material_override=material
	var material:=ShaderMaterial.new();material.shader=load("res://assets/environments/snow/shallow_polar_water.gdshader");material.set_shader_parameter("mask_type",2);detail.get_node("MeltwaterStream").material_override=material
	var packed:=PackedScene.new();packed.pack(detail);ResourceSaver.save(packed,"res://scenes/levels/polar_ice_lowland.tscn");detail.free();snow.queue_free();await process_frame
	print("LOCAL BANK FIT raised samples=",count,"; no region rollback performed");quit()
