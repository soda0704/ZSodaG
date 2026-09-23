shader_type spatial;
uniform vec4 rock_color : source_color = vec4(0.25, 0.29, 0.32, 1.0);
uniform vec4 snow_color : source_color = vec4(0.83, 0.89, 0.94, 1.0);
uniform float snow_threshold = 0.48;
uniform float detail_scale = 0.65;
varying vec3 world_pos;
varying vec3 world_normal;
float hash(vec3 p) { return fract(sin(dot(p, vec3(17.13, 81.7, 43.11))) * 43758.5453); }
float noise(vec3 p) { vec3 i=floor(p); vec3 f=fract(p); f=f*f*(3.0-2.0*f); return mix(mix(mix(hash(i), hash(i+vec3(1,0,0)),f.x),mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x),f.y),mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x),mix(hash(i+vec3(0,1,1)),hash(i+vec3(1,1,1)),f.x),f.y),f.z); }
void vertex() { world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; world_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL); }
void fragment() {
 float grain=noise(world_pos*detail_scale);
 float deposit=smoothstep(snow_threshold-0.08,snow_threshold+0.13,normalize(world_normal).y+(grain-0.5)*0.24);
 ALBEDO=mix(rock_color.rgb*(0.75+grain*0.4),snow_color.rgb*(0.92+grain*0.08),deposit);
 ROUGHNESS=0.96;
}
