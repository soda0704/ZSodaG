shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
uniform sampler2D albedo_atlas : source_color, filter_linear_mipmap;
uniform vec4 shadow_tint : source_color;
uniform vec4 highlight_tint : source_color;
uniform float tone_gain;
uniform float alpha_cutoff;
uniform float surface_roughness;
void fragment() {
 vec4 texel = texture(albedo_atlas, UV);
 float luminance = dot(texel.rgb, vec3(0.2126, 0.7152, 0.0722));
 float tone = clamp(sqrt(max(luminance, 0.0)) * tone_gain, 0.0, 1.0);
 ALBEDO = mix(shadow_tint.rgb, highlight_tint.rgb, tone);
 ALPHA = texel.a;
 ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
 ROUGHNESS = surface_roughness;
}
