shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled, depth_prepass_alpha;
uniform sampler2D ink_texture : source_color, filter_linear_mipmap_anisotropic;
uniform vec2 focus_atlas = vec2(0.28214285, 0.473631);
uniform vec2 window_extent = vec2(0.1285714, 0.1782178);
uniform float magnification : hint_range(1.0, 3.0) = 2.0;
void fragment() {
	float edge = length(UV - vec2(0.5));
	vec2 sample_at = focus_atlas + (UV - vec2(0.5)) * window_extent / magnification;
	vec4 ink = texture(ink_texture, sample_at);
	ALBEDO = ink.rgb;
	ROUGHNESS = 0.24;
	ALPHA = (1.0 - smoothstep(0.485, 0.5, edge)) * ink.a;
}
