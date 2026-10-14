shader_type spatial;
render_mode cull_disabled;

uniform sampler2D screen_texture : source_color, filter_linear;
uniform sampler2D error_texture : source_color, filter_linear;
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform sampler2D emissive_texture : source_color, filter_linear_mipmap;
uniform sampler2D metallic_roughness_texture : filter_linear_mipmap;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap;
// Bounds of the original blue display in the supplied material atlas.
uniform vec4 screen_atlas_rect;
uniform bool powered = false;
uniform bool key_missing = true;
uniform vec4 error_rect;
uniform vec4 error_text_color : source_color;
uniform float glitch_strength : hint_range(0.0, 0.2) = 0.065;
uniform float glitch_rate : hint_range(0.1, 20.0) = 5.0;
uniform float chromatic_offset : hint_range(0.0, 0.02) = 0.004;
uniform float emission_strength : hint_range(0.0, 3.0) = 1.15;
uniform float scanline_strength : hint_range(0.0, 0.2) = 0.025;
uniform float scanline_count = 488.0;
uniform float sweep_strength : hint_range(0.0, 0.1) = 0.012;

float glitch_noise(vec2 seed) {
	return fract(sin(dot(seed, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec3 original_emission = texture(emissive_texture, UV).rgb;
	ALBEDO = texture(albedo_texture, UV).rgb;
	vec3 metal_rough = texture(metallic_roughness_texture, UV).rgb;
	METALLIC = metal_rough.b;
	ROUGHNESS = metal_rough.g;
	NORMAL_MAP = texture(normal_texture, UV).rgb;
	EMISSION = original_emission * (powered ? 0.2 : 0.0);
	bool display_region = UV.x >= screen_atlas_rect.x && UV.y >= screen_atlas_rect.y
		&& UV.x <= screen_atlas_rect.z && UV.y <= screen_atlas_rect.w;
	// Use the original texture's luminous mask, leaving its frame and bevel untouched.
	float mask = display_region ? smoothstep(0.015, 0.08, min(original_emission.g, original_emission.b)) : 0.0;
	if (mask > 0.0) {
		vec2 screen_uv = vec2(
			(UV.y - screen_atlas_rect.y) / (screen_atlas_rect.w - screen_atlas_rect.y),
			(UV.x - screen_atlas_rect.x) / (screen_atlas_rect.z - screen_atlas_rect.x));
		vec3 color = vec3(0.004, 0.008, 0.009);
		if (powered) {
			color = texture(screen_texture, screen_uv).rgb;
			if (key_missing && screen_uv.x >= error_rect.x && screen_uv.y >= error_rect.y
					&& screen_uv.x <= error_rect.z && screen_uv.y <= error_rect.w) {
				vec2 error_uv = (screen_uv - error_rect.xy) / (error_rect.zw - error_rect.xy);
				float tick = floor(TIME * glitch_rate);
				float band = floor(error_uv.y * 16.0);
				float burst = step(0.5, glitch_noise(vec2(tick, 3.0)));
				error_uv.x += (glitch_noise(vec2(band, tick)) - 0.5) * glitch_strength * burst;
				float middle = texture(error_texture, error_uv).a;
				float red = texture(error_texture, error_uv + vec2(chromatic_offset, 0.0)).a;
				float blue = texture(error_texture, error_uv - vec2(chromatic_offset, 0.0)).a;
				float opacity = max(middle, max(red, blue));
				float flicker = 0.92 + 0.08 * glitch_noise(vec2(tick, band));
				vec3 error_color = vec3(red, middle, blue) * error_text_color.rgb * flicker;
				color = color * (1.0 - opacity) + error_color;
			}
			float lines = 1.0 - scanline_strength * (0.5 + 0.5 * sin(screen_uv.y * scanline_count * 6.28318));
			float sweep = sweep_strength * pow(max(0.0, 1.0 - abs(screen_uv.y - fract(TIME * 0.08)) * 18.0), 2.0);
			color = color * lines + vec3(sweep);
		}
		ALBEDO = mix(ALBEDO, powered ? vec3(0.0) : color, mask);
		METALLIC = mix(METALLIC, 0.0, mask);
		ROUGHNESS = mix(ROUGHNESS, 1.0, mask);
		EMISSION = mix(EMISSION, powered ? color * 0.35 : vec3(0.0), mask);
	}
}
