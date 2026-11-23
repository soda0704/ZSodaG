shader_type spatial;
render_mode unshaded, fog_disabled, depth_draw_never, depth_test_disabled, cull_disabled;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec3 clear_min[9];
uniform vec3 clear_max[9];
uniform mat4 base_inverse;
uniform float visibility_distance = 22.8;
uniform vec3 storm_color : source_color = vec3(0.73,0.80,0.88);
uniform float ground_height = -1000.0;
uniform float gust = 0.0;
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
 int count=0;
 for (int i=0;i<9;i++) {
  vec3 a=(clear_min[i]-origin)/safe_direction;
  vec3 b=(clear_max[i]-origin)/safe_direction;
  vec3 lo=min(a,b); vec3 hi=max(a,b);
  float enter=max(max(max(lo.x,lo.y),lo.z),0.0);
  float exit_distance=min(min(min(hi.x,hi.y),hi.z),distance_to_surface);
  if (enter<exit_distance) {
   int slot=count;
   while (slot>0) {
    if (intervals[slot-1].x<=enter) { break; }
    intervals[slot]=intervals[slot-1];
    slot--;
   }
   intervals[slot]=vec2(enter,exit_distance);
   count++;
  }
 }

 float covered=0.0;float end=0.0;
 for(int i=0;i<count;i++) { covered+=max(0.0,intervals[i].y-max(end,intervals[i].x));end=max(end,intervals[i].y); }
 float outdoors=max(0.0,distance_to_surface-covered);
 // Underground cave and lower floors keep their existing atmosphere.
 if(origin.y < -8.0 && target.y < -8.0) outdoors=0.0;
 // Broad wind-driven bands in world space, sampled along the exposed sightline.
 vec3 midpoint = mix(world, CAMERA_POSITION_WORLD, 0.58);
 vec2 drift = midpoint.xz * vec2(0.12, 0.23) - TIME * vec2(0.42, 0.17);
 float bands = 0.5 + 0.5 * sin(drift.y + sin(drift.x) * 1.4);
 float ground_fog = exp(-max(midpoint.y - ground_height, 0.0) * 0.67);
 float density = 1.0 + ground_fog * mix(0.08, 0.24, gust) * bands;
 float fog = smoothstep(2.5, visibility_distance, outdoors * density) * strength;
 float elevation = smoothstep(0.0, 0.56, direction.y);
 vec3 low_color = storm_color * vec3(0.88, 0.92, 0.96);
 vec3 sky_color = storm_color * vec3(0.79, 0.88, 0.99);
 ALBEDO = mix(low_color, sky_color, elevation);
 ALPHA = fog;
}
