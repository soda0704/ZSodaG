extends SceneTree
## Derive an impression's albedo/normal/ORM from the editable boot height SVG.
const DEST := "res://assets/environments/snow/entry_trial/"
func _initialize() -> void:
	var source := Image.new()
	if source.load_svg_from_string(FileAccess.get_file_as_string(DEST + "boot_relief.svg"), 2.0) != OK:
		quit(1); return
	var w := source.get_width(); var h := source.get_height()
	var heights := PackedFloat32Array(); heights.resize(w*h)
	var masks := PackedFloat32Array(); masks.resize(w*h)
	for y in h:
		for x in w:
			var pixel := source.get_pixel(x,y)
			heights[y*w+x] = (pixel.r - 0.63) * 0.026 * pixel.a
			masks[y*w+x] = pixel.a
	# Millimetre-scale softened compression edges, rather than a razor-sharp stamp.
	for pass_index in 3:
		var blurred := heights.duplicate()
		for y in range(1,h-1):
			for x in range(1,w-1):
				var i := y*w+x
				blurred[i] = (heights[i]*4 + heights[i-1]+heights[i+1]+heights[i-w]+heights[i+w]) / 8
		heights = blurred
	var albedo := Image.create(w,h,false,Image.FORMAT_RGBA8)
	var normal := Image.create(w,h,false,Image.FORMAT_RGBA8)
	var orm := Image.create(w,h,false,Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var i := y*w+x
			var depth := clampf(-heights[i]/0.012,0,1)
			var shade := lerpf(0.84,0.47,depth)
			albedo.set_pixel(x,y,Color(shade*0.94,shade*0.98,shade,masks[i]*0.82))
			var dx := (heights[y*w+mini(x+1,w-1)]-heights[y*w+maxi(x-1,0)]) / (0.25/w*2)
			var dy := (heights[mini(y+1,h-1)*w+x]-heights[maxi(y-1,0)*w+x]) / (0.40/h*2)
			var n := Vector3(-dx,dy,1.0).normalized()
			normal.set_pixel(x,y,Color(n.x*0.5+0.5,n.y*0.5+0.5,n.z*0.5+0.5,1))
			orm.set_pixel(x,y,Color(lerpf(1.0,0.78,depth),0.91,0,1))
	for pair in [[albedo,"boot_albedo.res"],[normal,"boot_normal.res"],[orm,"boot_orm.res"]]:
		var image: Image = pair[0]
		image.generate_mipmaps()
		if image.compress(Image.COMPRESS_BPTC) != OK: quit(1); return
		if ResourceSaver.save(ImageTexture.create_from_image(image),DEST+pair[1],ResourceSaver.FLAG_COMPRESS) != OK: quit(1); return
		print("BOOT PACKED ",pair[1]," ",w,"x",h)
	quit()
