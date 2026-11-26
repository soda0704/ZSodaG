shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D source : filter_linear, repeat_disable;
uniform vec2 blur_step;
uniform bool extract_highlights = false;

vec3 light_at(vec2 uv) {
	vec3 ink = texture(source, uv).rgb;
	if (extract_highlights) {
		float brightness = max(ink.r, max(ink.g, ink.b));
		ink *= smoothstep(0.07, 0.58, brightness);
	}
	return ink;
}

void fragment() {
	// Tight bloom carries the colour and the wider lobes soften the falloff.
	vec3 light = light_at(UV) * 0.24;
	light += (light_at(UV - blur_step * 1.4) + light_at(UV + blur_step * 1.4)) * 0.17;
	light += (light_at(UV - blur_step * 3.4) + light_at(UV + blur_step * 3.4)) * 0.11;
	light += (light_at(UV - blur_step * 6.5) + light_at(UV + blur_step * 6.5)) * 0.07;
	light += (light_at(UV - blur_step * 11.0) + light_at(UV + blur_step * 11.0)) * 0.03;
	COLOR = vec4(light, 1.0);
}
