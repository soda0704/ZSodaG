shader_type spatial;
uniform sampler2D snow_color : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D ice_detail : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D snow_normal : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D ice_normal : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform float formation_height=2.0;
varying vec3 world_position;
varying vec3 world_normal;
varying float local_height;
void vertex(){world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;world_normal=MODEL_NORMAL_MATRIX*NORMAL;local_height=VERTEX.y;}
void fragment(){
	float snow=smoothstep(.55,.85,normalize(world_normal).y)*smoothstep(formation_height*.3,formation_height*.75,local_height);
	vec3 ice=vec3(.34,.59,.65)*mix(.82,1.0,texture(ice_detail,world_position.xz*.22).r);
	vec3 powder=texture(snow_color,world_position.xz/2.4).rgb;
	vec4 packed=texture(snow_normal,world_position.xz/2.4);
	vec2 fine=mix((texture(ice_normal,world_position.xz*.35).rg*2.0-1.0)*.09,(packed.rg*2.0-1.0)*.28,snow);
	vec3 surface_normal=normalize(world_normal+vec3(fine.x,0.0,-fine.y));
	NORMAL=normalize((VIEW_MATRIX*vec4(surface_normal,0.0)).xyz);
	ALBEDO=mix(ice,powder,snow);ROUGHNESS=mix(.26,.86+packed.a*.12,snow);SPECULAR=mix(.50,.20,snow);
}
