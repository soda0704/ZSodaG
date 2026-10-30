shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;
uniform sampler2D ink_texture : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D paper_texture : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 paper_rect = vec4(-0.03, -0.03, 1.06, 1.06);
uniform bool live_atlas = false;
uniform vec2 focus_atlas = vec2(0.28214285, 0.473631);
uniform vec2 window_axis_x = vec2(0.1285714, 0.0);
uniform vec2 window_axis_y = vec2(0.0, 0.1782178);
uniform float magnification : hint_range(1.0, 3.0) = 2.0;
void fragment() {
	float edge = length(UV - vec2(0.5));
	vec2 offset = UV - vec2(0.5);
	vec2 sample_at = focus_atlas + (offset.x * window_axis_x + offset.y * window_axis_y) / magnification;
	vec4 ink = texture(ink_texture, sample_at);
	vec2 paper_at = live_atlas ? sample_at : vec2(0.1, 0.1866126) + sample_at * vec2(0.3642857, 0.5740365);
	vec4 paper = texture(paper_texture, (paper_at - paper_rect.xy) / paper_rect.zw);
	ALBEDO = mix(paper.rgb, ink.rgb, ink.a);
	ROUGHNESS = 0.24;
	ALPHA = 1.0 - smoothstep(0.485, 0.5, edge);
}
