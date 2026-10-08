extends Node3D
var created_usec := 0

func configure(texture:Texture2D,diameter:float,lifetime:float,fade_seconds:float) -> void:
 var sprite:Sprite3D=$Mark
 created_usec=Time.get_ticks_usec()
 sprite.texture=texture
 sprite.pixel_size=diameter/maxf(texture.get_width(),texture.get_height())
 add_to_group("weapon_impacts")
 var fade:=create_tween()
 fade.tween_interval(maxf(0.0,lifetime-fade_seconds))
 fade.tween_property(sprite,"modulate:a",0.0,minf(fade_seconds,lifetime))
 fade.tween_callback(queue_free)
