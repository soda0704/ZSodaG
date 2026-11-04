extends SceneTree
func _initialize():
 var image:=Image.load_from_file("res://assets/environments/snow/snow006/height.jpg")
 image.convert(Image.FORMAT_L8);image.generate_mipmaps()

 if ResourceSaver.save(ImageTexture.create_from_image(image),"res://assets/environments/snow/snow006/runtime_height.res",ResourceSaver.FLAG_COMPRESS)!=OK:quit(1);return
 print("SNOW HEIGHT R8 size=",image.get_size()," format=",image.get_format()," bytes=",image.get_data_size());quit()
