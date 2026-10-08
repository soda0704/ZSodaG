shader_type spatial;
render_mode cull_disabled;
uniform sampler2D needle_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 needle_tint : source_color = vec4(0.94, 0.98, 1.0, 1.0);
uniform vec4 snow_tint : source_color = vec4(0.82, 0.88, 0.92, 1.0);
uniform float snow_amount : hint_range(0.0, 1.0) = 0.58;
uniform float tree_variation : hint_range(0.0, 0.5) = 0.24;
uniform float patch_scale : hint_range(0.1, 4.0) = 1.5;
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.35;
varying vec3 snow_world_position;
varying vec3 snow_world_normal;
varying float tree_seed;
float snow_hash(vec3 p) { p=fract(p*0.1031); p+=dot(p,p.yzx+33.33); return fract((p.x+p.y)*p.z); }
float snow_noise(vec3 p) {
 vec3 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(mix(snow_hash(i),snow_hash(i+vec3(1,0,0)),f.x),mix(snow_hash(i+vec3(0,1,0)),snow_hash(i+vec3(1,1,0)),f.x),f.y),mix(mix(snow_hash(i+vec3(0,0,1)),snow_hash(i+vec3(1,0,1)),f.x),mix(snow_hash(i+vec3(0,1,1)),snow_hash(i+vec3(1,1,1)),f.x),f.y),f.z);
}
void vertex() {
 snow_world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
 snow_world_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL);
 tree_seed=snow_hash(floor(MODEL_MATRIX[3].xyz*0.7));
}
void fragment() {
 vec4 needles=texture(needle_texture,UV)*needle_tint;
 if (needles.a < alpha_cutoff) { discard; }
 float patches=snow_noise(snow_world_position*patch_scale);
 float amount=snow_amount+(tree_seed-0.5)*2.0*tree_variation;
 float up=max(normalize(snow_world_normal).y,0.0);
 float cover=smoothstep(0.40,0.72,amount+up*0.28+(patches-0.5)*0.75);
 ALBEDO=mix(needles.rgb,snow_tint.rgb*(0.92+patches*0.08),cover);
 ALPHA=needles.a;
 ALPHA_SCISSOR_THRESHOLD=alpha_cutoff;
 ROUGHNESS=0.94;
}
