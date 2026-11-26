shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

uniform sampler2D halo : filter_linear, repeat_disable;
uniform bool glow_enabled = true;
uniform vec2 motion_trail = vec2(0.0);

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec4 ink = texture(TEXTURE, UV);
	vec3 glow = glow_enabled ? texture(halo, UV).rgb : vec3(0.0);
	float shutter = smoothstep(0.003, 0.043, length(motion_trail));
	if (shutter > 0.0) {
		// Match the camera's centred shutter. Sample premultiplied ink so glyph
		// edges stay soft, and integrate the halo along the same exposure.
		vec4 exposure = vec4(0.0);
		vec3 glow_exposure = vec3(0.0);
		vec2 pixel = TEXTURE_PIXEL_SIZE * 0.5;
		for (int i = 0; i < 32; i++) {
			float phase = float(i) / 31.0 - 0.5;
			vec2 tap = clamp(UV + motion_trail * phase, pixel, vec2(1.0) - pixel);
			exposure += texture(TEXTURE, tap);
		}
		if (glow_enabled) {
			for (int i = 0; i < 8; i++) {
				float phase = float(i) / 7.0 - 0.5;
				glow_exposure += texture(halo, clamp(UV + motion_trail * phase, pixel, vec2(1.0) - pixel)).rgb;
			}
		}
		ink = mix(ink, exposure / 32.0, shutter * 0.92);
		glow = mix(glow, glow_exposure / 8.0, shutter * 0.92);
	}
	float peak = max(glow.r, max(glow.g, glow.b));
	// Compress the bright end and preserve the opacity of the original glyph.
	glow *= (0.78 / (1.0 + peak * 4.0)) * (1.0 - ink.a);
	COLOR = vec4((ink.rgb + glow) * tint.rgb * tint.a, ink.a * tint.a);
}
