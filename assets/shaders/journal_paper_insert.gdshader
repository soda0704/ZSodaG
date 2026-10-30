shader_type spatial;
render_mode cull_disabled;
uniform sampler2D ink_texture : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D back_ink_texture : source_color, filter_linear_mipmap_anisotropic;
uniform bool printed_back = false;
uniform vec4 back_source_rect = vec4(0.5, 0.0, 0.5, 1.0);
uniform float curl_amount = 0.0;
uniform vec4 source_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 panel_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 paper_back : source_color = vec4(0.89, 0.88, 0.84, 0.65);
uniform sampler2D paper_texture : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 paper_rect = vec4(-0.03, -0.03, 1.06, 1.06);
uniform vec4 paper_source_rect = vec4(0.1, 0.1866126, 0.3642857, 0.5740365);
void vertex() {
	VERTEX.z += curl_amount * sin(UV.x * 3.14159265) * (0.6 + 0.4 * UV.y);
}
void fragment() {
	vec2 cell = panel_rect.xy + UV * panel_rect.zw;
	vec4 ink = texture(ink_texture, source_rect.xy + cell * source_rect.zw);
	// Follow the plan's paper outline; transparent aspect/corner pixels are
	// the underlying book, not a second opaque rectangular paper border.
	// The SVG also contains a faint (12%) painted shadow outside its paper.
	// It must not become opaque paper; ContactShadow owns that footprint.
	if (!printed_back && ink.a < 0.20) discard;
	vec2 paper_at = paper_source_rect.xy + cell * paper_source_rect.zw;
	vec4 paper = texture(paper_texture, (paper_at - paper_rect.xy) / paper_rect.zw);
	if (printed_back) {
		// Native book UVs: the leaf must match the stationary paper at landing.
		vec2 paper_uv = FRONT_FACING ? vec2(0.065 + UV.x * 0.422, 0.06 + UV.y * 0.857)
			: vec2(0.515 + (1.0 - UV.x) * 0.422, 0.06 + UV.y * 0.857);
		paper = texture(paper_texture, paper_uv);
	}
	if (!FRONT_FACING && printed_back) {
		ink = texture(back_ink_texture, back_source_rect.xy + vec2(1.0 - UV.x, UV.y) * back_source_rect.zw);
	}
	if (max(paper.a, ink.a) < 0.05) discard;
	ALBEDO = FRONT_FACING || printed_back ? mix(paper.rgb, ink.rgb, ink.a) : mix(paper.rgb, paper_back.rgb, paper_back.a);
	ROUGHNESS = 0.96;
}
