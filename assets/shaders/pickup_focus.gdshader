shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 0.20);
uniform float outline_width_pixels : hint_range(0.25, 4.0) = 1.25;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec2 direction = (MODELVIEW_NORMAL_MATRIX * NORMAL).xy;
	direction /= max(length(direction), 0.001);
	clip.xy += direction * outline_width_pixels * 2.0 / VIEWPORT_SIZE * clip.w;
	POSITION = clip;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a;
}
