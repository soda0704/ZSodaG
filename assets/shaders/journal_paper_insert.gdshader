shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled, depth_prepass_alpha;
uniform sampler2D ink_texture : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 source_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 panel_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 paper_back : source_color = vec4(0.76, 0.71, 0.58, 1.0);
void fragment() {
	vec2 cell = panel_rect.xy + UV * panel_rect.zw;
	vec4 ink = texture(ink_texture, source_rect.xy + cell * source_rect.zw);
	ALBEDO = FRONT_FACING ? ink.rgb : paper_back.rgb;
	ALPHA = ink.a;
	ROUGHNESS = 0.96;
}
