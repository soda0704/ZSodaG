shader_type spatial;
render_mode cull_disabled;
uniform sampler2D limestone_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D damp_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D scree_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform float wall_scale : hint_range(0.05, 2.0) = 0.25;
uniform float floor_scale : hint_range(0.05, 2.0) = 0.5;
uniform float damp_coverage : hint_range(0.0, 1.0) = 0.25;
varying vec3 position_world;
varying vec3 normal_world;
void vertex() {
 position_world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
 normal_world=normalize(MODEL_NORMAL_MATRIX*NORMAL);
}
vec3 projected(sampler2D map, vec3 p, vec3 weights) {
 return texture(map,p.yz).rgb*weights.x+texture(map,p.xz).rgb*weights.y+texture(map,p.xy).rgb*weights.z;
}
void fragment() {
 vec3 n=normalize(normal_world);
 vec3 weights=pow(abs(n),vec3(4.0));weights/=max(dot(weights,vec3(1.0)),0.001);
 float damp=smoothstep(0.7,1.5,sin(position_world.x*0.14+position_world.y*0.17)+cos(position_world.z*0.18-position_world.y*0.09))*damp_coverage;
 vec3 stone=mix(projected(limestone_albedo,position_world*wall_scale,weights),projected(damp_albedo,position_world*wall_scale,weights),damp);
 float ground=smoothstep(0.65,0.92,n.y);
 ALBEDO=mix(stone,projected(scree_albedo,position_world*floor_scale,weights),ground*0.85);
 ROUGHNESS=mix(0.95,0.68,damp);
}
