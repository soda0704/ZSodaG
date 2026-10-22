shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform sampler2D turbulence : repeat_enable, filter_linear_mipmap;
uniform vec4 hot_tint : source_color = vec4(1.0, 0.81, 0.44, 1.0);
uniform vec4 cool_tint : source_color = vec4(0.55, 0.045, 0.006, 1.0);
uniform float emission_energy : hint_range(0.0, 8.0) = 1.8;
uniform float opacity : hint_range(0.0, 1.0) = 0.8;
uniform float erosion : hint_range(0.0, 1.0) = 0.45;
uniform float scroll_speed = 0.8;
uniform bool smoke = false;
instance uniform vec4 stop_plane = vec4(0.0, 0.0, 0.0, -1000.0);
varying float age;
varying float roll;
varying vec3 world_position;
void vertex() {
	age = INSTANCE_CUSTOM.y;
	roll = INSTANCE_CUSTOM.x;
	// World-space particle positions; camera-facing quads retain native particle scale.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz),
		INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz),
		INV_VIEW_MATRIX[2] * length(MODEL_MATRIX[2].xyz), MODEL_MATRIX[3]);
	world_position = (INV_VIEW_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	if (dot(vec4(world_position,1.0), stop_plane) > 0.0) discard;
	vec2 p = UV - vec2(0.5);
	p = mat2(vec2(cos(roll),-sin(roll)),vec2(sin(roll),cos(roll))) * p;
	vec2 uv = p + vec2(0.5);
	float n = texture(turbulence, uv * vec2(1.8,1.3) + vec2(age * 0.31, -TIME * scroll_speed)).r;
	float detail = texture(turbulence, uv * 4.2 + vec2(TIME * 0.12, age)).r;
	float shape = 1.0 - length(p * vec2(2.1,1.85));
	float density = smoothstep(erosion - 0.15, erosion + 0.20, shape + (n - 0.5) * 0.75 + (detail - 0.5) * 0.18);
	float fade = smoothstep(0.0, 0.08, age) * (1.0 - smoothstep(0.64,1.0,age));
	float heat = clamp((1.0-age) * 0.78 + n * 0.35,0.0,1.0);
	vec3 tint = mix(cool_tint.rgb, hot_tint.rgb, pow(heat, 1.7));
	ALBEDO = tint;
	EMISSION = smoke ? vec3(0.0) : tint * emission_energy;
	ALPHA = density * fade * opacity;
}
