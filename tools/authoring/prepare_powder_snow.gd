extends SceneTree
## Isotropic sub-centimetre powder grains; no broad photographed grooves.
const DEST := "res://assets/environments/snow/entry_trial/"
func _initialize():run.call_deferred()
func noise_image(frequency: float, seed_value: int) -> Image:
	var noise:=FastNoiseLite.new();noise.seed=seed_value;noise.frequency=frequency
	noise.noise_type=FastNoiseLite.TYPE_SIMPLEX_SMOOTH;noise.fractal_octaves=3
	var texture:=NoiseTexture2D.new();texture.width=2048;texture.height=2048
	texture.seamless=true;texture.noise=noise
	await texture.changed
	return texture.get_image()
func run():
	var grain:Image=await noise_image(0.24,3184)
	var clusters:Image=await noise_image(0.045,8702)
	var size:=2048
	var heights:=PackedFloat32Array();heights.resize(size*size)
	for y in size:
		for x in size:
			heights[y*size+x]=(grain.get_pixel(x,y).r-0.5)*0.0012+(clusters.get_pixel(x,y).r-0.5)*0.0006
	var color:=Image.create(size,size,false,Image.FORMAT_RGBA8)
	var normal:=Image.create(size,size,false,Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var g:=grain.get_pixel(x,y).r-0.5;var c:=clusters.get_pixel(x,y).r-0.5
			var value:=0.91+g*0.035+c*0.015
			color.set_pixel(x,y,Color(value*0.99,value*0.995,value,1))
			var dx:float=(heights[y*size+(x+1)%size]-heights[y*size+(x-1+size)%size])/(4.0/size)
			var dy:float=(heights[((y+1)%size)*size+x]-heights[((y-1+size)%size)*size+x])/(4.0/size)
			var n:=Vector3(-dx,dy,1).normalized()
			normal.set_pixel(x,y,Color(n.x*.5+.5,n.y*.5+.5,n.z*.5+.5,0.94+g*0.04))
	for pair in [[color,"powder_albedo.res"],[normal,"powder_normal_rough.res"]]:
		var image:Image=pair[0];image.generate_mipmaps()
		if image.compress(Image.COMPRESS_BPTC)!=OK:quit(1);return
		if ResourceSaver.save(ImageTexture.create_from_image(image),DEST+pair[1],ResourceSaver.FLAG_COMPRESS)!=OK:quit(1);return
		print("POWDER ",pair[1]," bytes=",image.get_data_size())
	quit()
