extends SceneTree
## Pack native-resolution generated snow, preserving actual source dimensions.
const DIR:="res://assets/environments/snow/arctic_powder_native/"
func _initialize():
 var albedo:=Image.load_from_file(DIR+"arctic_snow_albedo.png")
 var normal:=Image.load_from_file(DIR+"arctic_snow_normal_gl.png")
 var rough:=Image.load_from_file(DIR+"arctic_snow_roughness.png")
 var ao:=Image.load_from_file(DIR+"arctic_snow_ao.png")
 if albedo==null or normal==null or rough==null or ao==null:quit(1);return
 albedo.convert(Image.FORMAT_RGBA8);normal.convert(Image.FORMAT_RGBA8);rough.convert(Image.FORMAT_L8);ao.convert(Image.FORMAT_L8)
 var color_data:=albedo.get_data();var normal_data:=normal.get_data();var rough_data:=rough.get_data();var ao_data:=ao.get_data()
 for i in rough_data.size():color_data[i*4+3]=ao_data[i];normal_data[i*4+3]=rough_data[i]
 albedo=Image.create_from_data(albedo.get_width(),albedo.get_height(),false,Image.FORMAT_RGBA8,color_data)
 normal=Image.create_from_data(normal.get_width(),normal.get_height(),false,Image.FORMAT_RGBA8,normal_data)
 for pair in [[albedo,"runtime_albedo_ao.res"],[normal,"runtime_normal_rough.res"]]:
  var image:Image=pair[0];image.generate_mipmaps()
  var error:=image.compress(Image.COMPRESS_BPTC)
  if error!=OK:push_error("Native BC7 compression failed: "+str(error));quit(1);return
  if ResourceSaver.save(ImageTexture.create_from_image(image),DIR+pair[1],ResourceSaver.FLAG_COMPRESS)!=OK:quit(1);return
  print("NATIVE SNOW ",pair[1]," size=",image.get_size()," format=",image.get_format()," bytes=",image.get_data_size())
 quit()
