shader_type spatial;
render_mode unshaded, fog_disabled, depth_draw_never, depth_test_disabled, cull_disabled;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec3 clear_min[9];
uniform vec3 clear_max[9];
uniform mat4 base_inverse;
uniform float visibility_distance = 22.8;
uniform vec3 storm_color : source_color = vec3(0.64,0.71,0.76);
uniform float strength = 1.0;
void vertex() { POSITION = vec4(VERTEX.xy, 1.0, 1.0); }
void fragment() {
 float depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
 vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
 vec3 world = (INV_VIEW_MATRIX * vec4(view.xyz / view.w, 1.0)).xyz;
 vec3 origin = (base_inverse * vec4(CAMERA_POSITION_WORLD,1.0)).xyz;
 vec3 target = (base_inverse * vec4(world,1.0)).xyz;
 float distance_to_surface = min(length(target-origin), 150.0);
 vec3 direction = normalize(target-origin);
 vec3 safe_direction = mix(vec3(0.00001), direction, greaterThan(abs(direction),vec3(0.00001)));
 vec2 intervals[9];
 for (int i=0;i<9;i++) {
  vec3 a=(clear_min[i]-origin)/safe_direction;
  vec3 b=(clear_max[i]-origin)/safe_direction;
  vec3 lo=min(a,b); vec3 hi=max(a,b);
  intervals[i]=vec2(clamp(max(max(lo.x,lo.y),lo.z),0.0,distance_to_surface),clamp(min(min(hi.x,hi.y),hi.z),0.0,distance_to_surface));
 }
 for(int i=0;i<9;i++) { for(int j=i+1;j<9;j++) { if(intervals[j].x<intervals[i].x) {vec2 temp=intervals[i];intervals[i]=intervals[j];intervals[j]=temp;} } }
 float covered=0.0;float end=0.0;
 for(int i=0;i<9;i++) { covered+=max(0.0,intervals[i].y-max(end,intervals[i].x));end=max(end,intervals[i].y); }
 float outdoors=max(0.0,distance_to_surface-covered);
 // Underground cave and lower floors keep their existing atmosphere.
 if(origin.y < -8.0 && target.y < -8.0) outdoors=0.0;
 float fog=smoothstep(2.0,visibility_distance,outdoors)*strength;
 ALBEDO=storm_color; ALPHA=fog;
}
