shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
uniform float opacity : hint_range(0.0, 1.0) = 0.55;
uniform float softness : hint_range(0.005, 0.25) = 0.035;
void fragment() {
	vec2 edge = abs(UV - vec2(0.5)) - vec2(0.5 - softness);
	float distance_to_edge = length(max(edge, vec2(0.0))) + min(max(edge.x, edge.y), 0.0);
	float coverage = 1.0 - smoothstep(-softness, softness, distance_to_edge);
	ALBEDO = vec3(0.09, 0.07, 0.05);
	// The glued edge stays in contact; the raised free edge casts more shade.
	ALPHA = opacity * coverage * mix(0.35, 1.0, UV.x);
}
