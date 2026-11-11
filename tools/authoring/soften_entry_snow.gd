extends SceneTree
func _initialize():run.call_deferred()
func run():
	var path:="res://assets/environments/snow/expanded_terrain/terrain3d-01_00.res"
	var backup:="res://tools/.local/entry-snow-2026-11-11.res"
	if FileAccess.file_exists(backup):push_error("Entry snow already shaped");quit(1);return
	DirAccess.copy_absolute(path,backup)
	var region=load(path);var image:Image=region.get_height_map().duplicate();var count:=0
	for x in range(-48,-37):
		for z in range(0,8):
			var old:float=image.get_pixel(x+256,z).r
			var approach:=smoothstep(-47,-40,float(x))*(1-smoothstep(-39,-37,float(x)))
			var width:=1.1+maxf(0,-41-x)*.15
			var across:=1-smoothstep(width*.35,width+1.0,absf(z-3.0))
			var target:=lerpf(old,maxf(old,-.035),approach*across)
			# Low irregular snow shoulders taper out before the door sweep.
			var shoulder:=exp(-pow((x+42.5)/2.0,2))*exp(-pow((absf(z-3.0)-2.2)/.9,2))*.11
			target+=shoulder*(1-smoothstep(-40.5,-39.2,float(x)))
			if absf(target-old)>.001:image.set_pixel(x+256,z,Color(target,0,0,1));count+=1
	region.location=Vector2i(-1,0);region.set_height_map(image);region.set_modified(true);assert(region.save(path,false)==OK)
	print("PASS softened entry snow samples=",count);quit()
