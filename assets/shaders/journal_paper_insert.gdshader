shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled, depth_prepass_alpha;
uniform sampler2D ink_texture : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 source_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 panel_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 paper_back : source_color = vec4(0.89, 0.88, 0.84, 0.65);
uniform sampler2D paper_texture : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 paper_rect = vec4(-0.03, -0.03, 1.06, 1.06);
uniform vec4 paper_source_rect = vec4(0.1, 0.1866126, 0.3642857, 0.5740365);
void fragment() {
	vec2 cell = panel_rect.xy + UV * panel_rect.zw;
	vec4 ink = texture(ink_texture, source_rect.xy + cell * source_rect.zw);
	vec2 paper_at = paper_source_rect.xy + cell * paper_source_rect.zw;
	vec4 paper = texture(paper_texture, (paper_at - paper_rect.xy) / paper_rect.zw);
	ALBEDO = FRONT_FACING ? mix(paper.rgb, ink.rgb, ink.a) : mix(paper.rgb, paper_back.rgb, paper_back.a);
	ALPHA = max(paper.a, ink.a);
	ROUGHNESS = 0.96;
}
