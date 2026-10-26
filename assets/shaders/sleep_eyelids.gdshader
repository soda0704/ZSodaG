shader_type canvas_item;
uniform float openness : hint_range(0.0, 1.0) = 1.0;
void fragment() {
	float across = UV.x * 2.0 - 1.0;
	float half_gap = openness * (0.55 + (1.0 - openness) * 0.2 * (1.0 - across * across));
	float lid = smoothstep(half_gap - 0.008, half_gap + 0.008, abs(UV.y - 0.5));
	COLOR = vec4(0.0, 0.0, 0.0, openness < 0.001 ? 1.0 : lid);
}
