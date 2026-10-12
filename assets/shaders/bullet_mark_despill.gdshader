shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;

uniform sampler2D mark_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;

void fragment() {
 vec4 mark = texture(mark_texture, UV);
 float neutral = max(mark.r, mark.b);
 float green_spill = max(mark.g - neutral, 0.0);
 // Remove the keyed fringe; transparency reveals the actual hit surface.
 float edge_coverage = 1.0 - smoothstep(0.02, 0.11, green_spill);
 mark.g = min(mark.g, neutral);
 ALBEDO = mark.rgb;
 ALPHA = mark.a * edge_coverage * opacity;
 ROUGHNESS = 1.0;
 SPECULAR = 0.0;
}
