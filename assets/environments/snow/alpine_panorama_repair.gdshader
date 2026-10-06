shader_type sky;
// Preserve the 8K HDR panorama; replace only its broken mountain faces.
uniform sampler2D panorama : source_color, filter_linear_mipmap, repeat_enable;
// The reference PNG was exported from linear HDR, so its patch stays linear.
uniform sampler2D repair_panorama : filter_linear_mipmap, repeat_enable;
uniform vec4 repair_bounds = vec4(0.0);
uniform float repair_feather : hint_range(0.0, 0.02) = 0.004;
void sky() {
 vec2 uv = SKY_COORDS;
 vec2 lower = smoothstep(repair_bounds.xy, repair_bounds.xy + vec2(repair_feather), uv);
 vec2 upper = vec2(1.0) - smoothstep(repair_bounds.zw - vec2(repair_feather), repair_bounds.zw, uv);
 float weight = lower.x * lower.y * upper.x * upper.y;
 COLOR = mix(texture(panorama, uv).rgb, texture(repair_panorama, uv).rgb, weight);
}
