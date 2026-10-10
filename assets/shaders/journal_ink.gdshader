shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;
uniform sampler2D ink_texture : source_color, filter_linear_mipmap_anisotropic;
uniform float atlas_offset = 0.0;
void fragment() {
	vec4 ink = texture(ink_texture, UV * vec2(0.5, 1.0) + vec2(atlas_offset, 0.0));
	ALBEDO = ink.rgb;
	ALPHA = ink.a;
	ROUGHNESS = 0.94;
}
