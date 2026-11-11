extends SceneTree
# Desktop Forward+ textures: original 2K maps, mipmaps and BC7 GPU compression.
func _initialize():
	for map in ["color","normalgl","roughness"]:
		var image=Image.load_from_file("res://assets/environments/snow/ice003/ice003_"+map+".jpg")
		assert(image!=null and image.get_size()==Vector2i(2048,2048))
		image.generate_mipmaps()
		assert(image.compress(Image.COMPRESS_BPTC)==OK)
		assert(ResourceSaver.save(ImageTexture.create_from_image(image),"res://assets/environments/snow/ice003/"+map+".res")==OK)
	print("PASS Ice003 original 2K BC7 maps with mipmaps");quit()
