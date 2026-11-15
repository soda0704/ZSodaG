shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform float opacity = 0.65;
uniform vec3 flake_color : source_color = vec3(0.94, 0.97, 1.0);
uniform vec3 wind_direction = vec3(1.0, -0.2, 0.4);
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
 float exposure=mix(0.25,1.0,clamp(speed,0.0,1.5)/1.5);
 // Compact snow grains acquire short exposure trails and soft near-lens defocus.
 float width=mix(1.0,2.3,close);
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
 float asymmetry=q.y+sin(q.x*4.0+flake_seed*23.0)*0.12;
 float grain=exp(-q.x*q.x*4.0-asymmetry*asymmetry*5.0);
 float tail=exp(-q.y*q.y*6.0)*(1.0-smoothstep(0.2,1.0,abs(q.x)));
 float shape=mix(grain,tail,0.32);
 float near_fade=smoothstep(0.16,0.65,camera_distance);
 float far_fade=1.0-smoothstep(7.0,17.0,camera_distance);
 float brightness=mix(0.48,0.95,flake_seed);
 ALBEDO=flake_color;
 ALPHA=inside?0.0:shape*opacity*near_fade*far_fade*brightness;
}
