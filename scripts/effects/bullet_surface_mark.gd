extends Node3D
const CONCRETE_DESPILL := preload("res://assets/shaders/bullet_mark_despill.gdshader")
var created_usec := 0

func configure(texture:Texture2D,diameter:float,lifetime:float,fade_seconds:float) -> void:
 var sprite:Sprite3D=$Mark
 created_usec=Time.get_ticks_usec()
 sprite.texture=texture
 sprite.pixel_size=diameter/maxf(texture.get_width(),texture.get_height())
 var source:Texture2D=texture.atlas if texture is AtlasTexture else texture
 var edge_material:ShaderMaterial
 if source.resource_path.ends_with("/concrete_atlas.png"):
  edge_material=ShaderMaterial.new()
  edge_material.shader=CONCRETE_DESPILL
  edge_material.set_shader_parameter("mark_texture",source)
  sprite.material_override=edge_material
 add_to_group("weapon_impacts")
 var fade:=create_tween()
 fade.tween_interval(maxf(0.0,lifetime-fade_seconds))
 if edge_material!=null:
  fade.tween_method(func(value:float): edge_material.set_shader_parameter("opacity",value),1.0,0.0,minf(fade_seconds,lifetime))
 else:
  fade.tween_property(sprite,"modulate:a",0.0,minf(fade_seconds,lifetime))
 fade.tween_callback(queue_free)
