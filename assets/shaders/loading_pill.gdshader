// Pill Slider — https://godotshaders.com/shader/pill-slider/ — CC0.
// NorthernLab: exact endpoints, optional handle, pixel-sized antialiasing.
shader_type canvas_item;

/*
	Pill Slider
	-----------
	A stylized progress/slider fill shader: rounded "pill" shaped track,
	a color gradient fill that grows with `fill_ratio`, a soft pulsing
	glow at the fill's edge, and a clean circular handle that always
	stays round regardless of the node's width/height ratio.

	USAGE
	-----
	1. Apply this shader to a ColorRect (or any CanvasItem) that covers
	   the area of your slider. The ColorRect's `color` should stay
	   white (1,1,1,1) so it doesn't tint the shader's output.
	2. Set `slider_aspect` to (node_width / node_height) so the handle
	   renders as a perfect circle. Recalculate it whenever the node
	   is resized.
	3. Drive `fill_ratio` (0.0 - 1.0) from script to represent your
	   slider's current value, e.g.:

	   var ratio: float = (value - min_value) / (max_value - min_value)
	   material.set_shader_parameter("fill_ratio", ratio)

	   Animate it with a Tween for a smooth transition.

	All other motion (the edge glow pulse) runs automatically off TIME,
	no extra script logic required.
*/

// ---------------------------------------------------------------------
// Track (background pill shape)
// ---------------------------------------------------------------------
uniform vec4 track_color : source_color = vec4(0.09, 0.09, 0.11, 1.0);
uniform vec4 track_border_color : source_color = vec4(0.0, 0.0, 0.0, 0.5);
uniform float corner_radius : hint_range(0.0, 0.5) = 0.4; // in "height units", 0.5 = full pill
uniform float border_width : hint_range(0.0, 0.1) = 0.05;

// ---------------------------------------------------------------------
// Fill gradient
// ---------------------------------------------------------------------
uniform vec4 color_min : source_color = vec4(0.35, 0.55, 0.95, 1.0); // color at min_value
uniform vec4 color_max : source_color = vec4(0.55, 0.85, 0.55, 1.0); // color at max_value
uniform float fill_ratio : hint_range(0.0, 1.0) = 0.35; // drive this from script
uniform float edge_softness : hint_range(0.0, 0.2) = 0.015;

// ---------------------------------------------------------------------
// Edge glow (pulses gently at the tip of the fill, purely time-driven)
// ---------------------------------------------------------------------
uniform float tip_glow_width : hint_range(0.0, 0.2) = 0.03;
uniform float tip_glow_strength : hint_range(0.0, 0.5) = 0.15;
uniform float tip_pulse_speed : hint_range(0.0, 5.0) = 1.2;

// ---------------------------------------------------------------------
// Handle (always circular, independent of node aspect ratio)
// ---------------------------------------------------------------------
uniform vec4 handle_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 handle_outline_color : source_color = vec4(0.15, 0.15, 0.18, 0.9);
uniform float handle_radius : hint_range(0.0, 0.5) = 0.32; // in "height units"
uniform float handle_outline_width : hint_range(0.0, 0.1) = 0.03;
uniform float handle_shadow_strength : hint_range(0.0, 1.0) = 0.25;

// Node width / node height. MUST be updated from script whenever the
// node is resized, otherwise the handle will render as an ellipse.
uniform float slider_aspect : hint_range(1.0, 100.0) = 10.0;


// Signed distance field for a rounded box, centered at origin.
float rounded_box_sdf(vec2 point, vec2 half_size, float radius) {
	vec2 q = abs(point) - half_size + radius;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

// A padded canvas leaves room for a 9px light and its halo around the 4px track.
uniform float track_half_height = 0.0625;
void fragment() {
 vec2 p=(UV-0.5)*vec2(slider_aspect,1.0);
 float distance=rounded_box_sdf(p,vec2(slider_aspect*0.5,track_half_height),track_half_height);
 float aa=max(fwidth(distance),0.001);
 float track=1.0-smoothstep(-aa,aa,distance);
 float filled=fill_ratio<=0.0?0.0:(fill_ratio>=1.0?1.0:1.0-smoothstep(fill_ratio-edge_softness,fill_ratio+edge_softness,UV.x));
 vec4 gradient=mix(color_min,color_max,UV.x);
 vec3 base=mix(track_color.rgb,gradient.rgb,filled);
 float alpha=track*mix(track_color.a,gradient.a,filled);
 float inset=0.48/slider_aspect;
 float position=clamp(fill_ratio,inset,1.0-inset);
 vec2 light=vec2((UV.x-position)*slider_aspect,UV.y-0.5);
 float radius=length(light);
 float pulse=0.92+0.08*sin(TIME*tip_pulse_speed);
 float halo=exp(-dot(light,light)/0.055)*0.68*pulse;
 float inner_halo=exp(-dot(light,light)/0.012)*0.58;
 float glow_alpha=clamp(halo+inner_halo,0.0,0.94);
 vec3 glow_color=vec3(0.54,0.86,1.0);
 vec3 premultiplied=base*alpha+glow_color*glow_alpha*(1.0-alpha);
 alpha+=glow_alpha*(1.0-alpha);
 float core=1.0-smoothstep(handle_radius-aa,handle_radius+aa,radius);
 premultiplied=mix(premultiplied,handle_color.rgb,core);
 alpha=mix(alpha,1.0,core);
 COLOR=vec4(premultiplied/max(alpha,0.0001),alpha);
}
