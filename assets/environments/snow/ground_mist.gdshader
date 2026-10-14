shader_type fog;
// Broad, world-anchored mist. No temporal animation or thin moving sheets.
uniform float density : hint_range(0.0, 0.02) = 0.004;
void fog() {
	vec3 p = WORLD_POSITION;
	float terrain_band = exp(-max(p.y - 1.0, 0.0) / 9.0);
	float above_ground = smoothstep(-1.0, 1.0, p.y);
	float base_distance = max(abs(p.x + 4.5) - 43.5, abs(p.z - 1.5) - 32.5);
	float outside_base = smoothstep(0.0, 7.0, base_distance);
	float variation = 0.72 + 0.14 * sin(p.x * 0.035 + p.z * 0.02)
		+ 0.14 * sin(p.z * 0.047 - p.x * 0.013);
	DENSITY = density * terrain_band * above_ground * outside_base * variation;
	ALBEDO = vec3(0.78, 0.85, 0.93);
}
