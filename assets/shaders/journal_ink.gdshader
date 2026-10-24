shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled, depth_prepass_alpha;
uniform sampler2D ink_texture : source_color, filter_linear_mipmap_anisotropic;
uniform float atlas_offset = 0.0;
uniform bool map_cutout = false;
uniform vec4 map_rect = vec4(0.1, 0.1866126, 0.3642857, 0.5740365);
uniform sampler2D paper_texture : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 paper_rect = vec4(-0.03, -0.03, 1.06, 1.06);
void fragment() {
	vec2 at = UV * vec2(0.5, 1.0) + vec2(atlas_offset, 0.0);
	vec4 ink = texture(ink_texture, at);
	if (map_cutout && all(greaterThanEqual(at, map_rect.xy)) && all(lessThanEqual(at, map_rect.xy + map_rect.zw))) ink = texture(paper_texture, (at - paper_rect.xy) / paper_rect.zw);
	ALBEDO = ink.rgb;
	ALPHA = ink.a;
	ROUGHNESS = 0.94;
}
