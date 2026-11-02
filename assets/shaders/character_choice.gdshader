shader_type canvas_item;
render_mode blend_premul_alpha;
uniform float highlight : hint_range(0.0, 1.0) = 0.0;
uniform float entrance : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 body = texture(TEXTURE, UV);
	vec2 step_uv = TEXTURE_PIXEL_SIZE * 3.0;
	float edge = 0.0;
	edge = max(edge, texture(TEXTURE, UV + vec2(step_uv.x, 0.0)).a);
	edge = max(edge, texture(TEXTURE, UV - vec2(step_uv.x, 0.0)).a);
	edge = max(edge, texture(TEXTURE, UV + vec2(0.0, step_uv.y)).a);
	edge = max(edge, texture(TEXTURE, UV - vec2(0.0, step_uv.y)).a);
	float outline = max(0.0, edge - body.a);
	vec3 tint = mix(vec3(0.0), vec3(1.0), highlight);
	float brightness = mix(0.018, 1.0, highlight);
	float opacity = mix(0.85, 1.0, highlight);
	vec3 body_color = body.a > 0.0 ? body.rgb : vec3(0.0);
	// The idle silhouette is almost black with a little background showing through.
	COLOR = vec4(body_color * brightness + tint * outline, max(body.a, edge)) * opacity * entrance;
}
