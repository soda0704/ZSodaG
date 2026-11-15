shader_type canvas_item;
render_mode unshaded, blend_mix;

// Analytic optical pointer. Soft light without a dark outline.
uniform float energy : hint_range(0.0, 4.0) = 1.0;
uniform float spread : hint_range(0.5, 2.0) = 1.0;
uniform bool afterimage = false;
uniform vec2 trail_extent = vec2(48.0);
uniform float segment_length = 0.0;
uniform float click_wave : hint_range(0.0, 1.0) = 1.0;
uniform float click_strength : hint_range(0.0, 1.0) = 0.0;
float gaussian(float radius_squared, float sigma) {
 return exp(-radius_squared/(2.0*sigma*sigma));
}
void fragment() {
 vec2 point=(UV-0.5)*128.0;
 float radius=length(point);
 float radius_squared=dot(point,point);
 float fade=clamp(energy,0.0,1.0);
 if (afterimage) {
  vec2 tail=(UV-0.5)*trail_extent;
  tail.x=max(abs(tail.x)-segment_length*0.5,0.0);
  float tail_distance=dot(tail,tail);
  float opacity=(gaussian(tail_distance,1.0)*0.40+gaussian(tail_distance,2.0)*0.60)*energy;
  COLOR=vec4(1.0,0.23,0.10,opacity);
 } else {
  float core=1.0-smoothstep(1.1,2.1,radius);
  float halo=gaussian(radius_squared,2.5*spread)*0.38;
  float ring_radius=mix(2.5,7.0,click_wave);
  float ring=exp(-pow((radius-ring_radius)/1.25,2.0))*click_strength*0.16;
  float alpha=clamp(halo*fade+ring,0.0,1.0);
  vec3 rgb=vec3(1.0,0.16,0.065);
  // Warm white remains precise; the ring is visual only and never shifts the hotspot.
  rgb=mix(rgb,vec3(1.0,0.93,0.83),core);
  alpha=mix(alpha,fade,core);
  alpha*=1.0-smoothstep(45.0,60.0,radius);
  COLOR=vec4(rgb,alpha);
 }
}

