shader_type spatial;
render_mode cull_disabled, depth_draw_never;
uniform float opacity = 0.65;
uniform vec3 flake_color : source_color = vec3(0.94, 0.97, 1.0);
uniform vec3 haze_color : source_color = vec3(0.73,0.80,0.88);
uniform mat4 base_inverse;
uniform vec3 clear_min[9];
uniform vec3 clear_max[9];
varying vec3 world_point;
varying float flake_seed;
varying float camera_distance;
void vertex() {
 world_point=MODEL_MATRIX[3].xyz;
 flake_seed=INSTANCE_CUSTOM.w;
 vec3 center=(VIEW_MATRIX*vec4(world_point,1.0)).xyz;
 camera_distance=length(center);
 vec3 velocity=INSTANCE_CUSTOM.xyz;
 vec3 motion=(VIEW_MATRIX*vec4(velocity/16.0,0.0)).xyz;
 vec2 projected=motion.xy+center.xy*motion.z/max(-center.z,0.5);
 float speed=length(projected);
 vec2 along=speed>0.001?projected/speed:vec2(1.0,0.0);
 vec2 across=vec2(-along.y,along.x);
 float close=1.0-smoothstep(0.7,3.5,camera_distance);
 float powder=1.0-smoothstep(0.72,0.85,flake_seed);
 float size=mix(1.2,0.35+flake_seed*0.4,powder);
 float exposure=clamp(speed*1.25,0.18,2.1);
 // Compact snow grains acquire short exposure trails and soft near-lens defocus.
 float width=mix(0.72,1.3,close);
 vec2 offset=along*VERTEX.x*exposure+across*VERTEX.y*width;
 float scale=length(MODEL_MATRIX[0].xyz)*size;
 MODELVIEW_MATRIX=VIEW_MATRIX*mat4(INV_VIEW_MATRIX[0],INV_VIEW_MATRIX[1],INV_VIEW_MATRIX[2],MODEL_MATRIX[3]);
 VERTEX.xy=offset*scale;
}
void fragment() {
 vec3 p=(base_inverse*vec4(world_point,1.0)).xyz;
 bool inside=p.y< -8.0;
 for(int i=0;i<9;i++) {
  inside=inside||(all(greaterThan(p,clear_min[i]))&&all(lessThan(p,clear_max[i])));
 }
 vec2 q=(UV-0.5)*2.0;
 float centerline=sin(q.x*3.0+flake_seed*23.0)*0.08;
 float profile=(q.y-centerline)*2.5;
 float cross_section=exp(-profile*profile);
 float envelope=smoothstep(-1.0,-0.18,q.x)*(1.0-smoothstep(0.35,1.0,q.x));
 float shape=cross_section*envelope;
 float near_fade=smoothstep(0.12,0.48,camera_distance);
 float far_fade=1.0-smoothstep(9.0,20.0,camera_distance);
 float brightness=mix(0.54,1.0,flake_seed);
 vec3 snow=mix(flake_color,haze_color,smoothstep(3.0,17.0,camera_distance));
 ALBEDO=snow*0.16;
 EMISSION=snow*mix(0.65,0.95,1.0-smoothstep(1.0,6.0,camera_distance));
 ROUGHNESS=1.0;
 ALPHA=inside?0.0:shape*opacity*near_fade*far_fade*brightness;
}
void light() {
 if (!LIGHT_IS_DIRECTIONAL) {
  DIFFUSE_LIGHT+=LIGHT_COLOR*ATTENUATION*0.14;
 }
}
