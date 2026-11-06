// Realistic Photography Camera by TuniTem, CC0 1.0.
// https://godotshaders.com/shader/realistic-photography-camera/
// Screen effect from the published shader; project tuning lives in the scene.
// NorthernLab bodycam adaptation: lens, sensor grain, response curve and shutter.
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform vec2 resolution = vec2(1920, 1080);

group_uniforms Camera_Settings;
uniform float iso : hint_range(100, 25600, 100) = 400;
uniform float fstop : hint_range(1.0, 32.0, 0.1) = 2.8;
uniform float shutter_speed : hint_range(0.0001, 4.0, 0.0001) = 0.004;
uniform float set_ev : hint_range(-5.0, 5.0, 0.001) = 0.0;
group_uniforms Exposure;
uniform float base_ev = 17.621;

group_uniforms MotionBlur;
uniform bool motion_blur_enabled = false;
uniform vec2 blur_direction = vec2(0.0, 0.0);
uniform float radial_blur = 0.0;
uniform int samples : hint_range(4, 32) = 32;

group_uniforms Bodycam;
uniform float lens_amount : hint_range(0.0, 1.0) = 1.0;
uniform float barrel_strength : hint_range(0.0, 0.2) = 0.12;
uniform float chroma_pixels : hint_range(0.0, 2.0) = 0.65;
uniform float vignette_strength : hint_range(0.0, 1.0) = 1.0;
uniform float vignette_corner_size : hint_range(0.1, 0.5) = 0.3;
uniform float vignette_softness : hint_range(0.005, 0.2) = 0.12;
uniform vec2 vignette_offset = vec2(0.0);
uniform float response_curve : hint_range(0.0, 0.5) = 0.18;
uniform float saturation : hint_range(0.0, 1.2) = 0.84;
uniform float sensor_grain : hint_range(0.0, 0.15) = 0.07;
uniform float vhs_strength : hint_range(0.0, 1.0) = 0.18;
uniform float grain_size : hint_range(0.5, 3.0) = 0.85;

group_uniforms Noise_Settings;
uniform float noise_intensity : hint_range(0, 1.0, 0.001) = 0.5;
uniform float max_noise : hint_range(0.1, 2.0, 0.001) = 1.0;

// hash22 from https://www.shadertoy.com/view/lldyDn with a seed added.
vec2 hash22(vec2 uv, float seed) {
	uv += seed;
	vec3 p3 = fract(vec3(uv.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy) * 2.0 - 1.0;
}

// Perlin noise from https://godotshaders.com/snippet/2d-noise/
float noise(vec2 uv, float s) {
	vec2 uv_index = floor(uv);
	vec2 uv_fract = fract(uv);
	vec2 blur = smoothstep(0.0, 1.0, uv_fract);
	return mix(
		mix(dot(hash22(uv_index + vec2(0.0, 0.0), s), uv_fract - vec2(0.0, 0.0)),
			dot(hash22(uv_index + vec2(1.0, 0.0), s), uv_fract - vec2(1.0, 0.0)), blur.x),
		mix(dot(hash22(uv_index + vec2(0.0, 1.0), s), uv_fract - vec2(0.0, 1.0)),
			dot(hash22(uv_index + vec2(1.0, 1.0), s), uv_fract - vec2(1.0, 1.0)), blur.x),
		blur.y) + 0.5;
}

void fragment() {
	vec2 pixel = 1.0 / max(resolution, vec2(1.0));
	vec2 p = (SCREEN_UV - 0.5) * 2.0;
	float radius2 = dot(p, p);
	float lens = barrel_strength * lens_amount;
	// Overscan prevents wrapping and bright/black borders at the curved corners.
	vec2 uv = 0.5 + p * (1.0 + lens * radius2) / (1.0 + 2.0 * lens) * 0.5;
	uv = clamp(uv, pixel, 1.0 - pixel);
	// Sub-pixel horizontal tape instability, without rolling tears.
	uv.x += sin(SCREEN_UV.y * 130.0 + TIME * 5.0) * pixel.x * 0.45 * vhs_strength * lens_amount;
	vec4 centre = texture(screen_texture, uv);
	// Motion blur adapted by the author from the smooth-motion-blur shader.
	vec4 pixel_color;
	if (motion_blur_enabled) {
		vec4 color = vec4(0.0);
		float total_weight = 0.0;
		for (int i = 0; i < samples; i++) {
			float offset = float(i) / float(samples - 1) - 0.5;
			vec2 flow = blur_direction + (uv - 0.5) * radial_blur;
			color += texture(screen_texture, clamp(uv + flow * offset, pixel, 1.0 - pixel));
			total_weight += 1.0;
		}
		pixel_color = color / total_weight;
	} else {
		pixel_color = centre;
	}
	vec2 fringe = p * pixel * chroma_pixels * radius2 * lens_amount;
	pixel_color.r += texture(screen_texture, clamp(uv + fringe, pixel, 1.0 - pixel)).r - centre.r;
	pixel_color.b += texture(screen_texture, clamp(uv - fringe, pixel, 1.0 - pixel)).b - centre.b;
	uv.y *= resolution.y / resolution.x;
	float light_gathering = (1.0 / (fstop * fstop)) * shutter_speed;
	float scene_ev = set_ev + base_ev + log2(light_gathering * iso / 100.0);
	float exposure_multiplier = pow(2.0, scene_ev - 12.0);
	pixel_color.rgb *= exposure_multiplier;
	vec3 bounded = clamp(pixel_color.rgb, 0.0, 1.0);
	pixel_color.rgb = mix(pixel_color.rgb, bounded * bounded * (3.0 - 2.0 * bounded), response_curve);
	float luminance = dot(pixel_color.rgb, vec3(0.2126, 0.7152, 0.0722));
	pixel_color.rgb = mix(vec3(luminance), pixel_color.rgb, saturation);
	// White balance and grading belong to WorldEnvironment. The sensor/lens
	// pass must not add a second cyan cast on top of the scene lighting.
	// Small rounded lens-housing corners: the middle of every edge stays clear.
	// Follow the look input only near the corners, without introducing side bars.
	float rim_follow = smoothstep(0.6, 0.85, abs(p.x)) * smoothstep(0.6, 0.85, abs(p.y));
	vec2 rim_p = p - vignette_offset * vec2(2.0 * resolution.y / resolution.x, 2.0) * rim_follow;
	vec2 corner = max(abs(rim_p) - vec2(1.0 - vignette_corner_size), vec2(0.0)) / vignette_corner_size;
	float vignette = smoothstep(1.035, 1.035 + vignette_softness, length(corner));
	float photon_noise_factor = sqrt(1.0 / max(light_gathering, 0.0001));
	float read_noise_factor = sqrt(iso / 100.0);
	float noise_amplifier = photon_noise_factor * read_noise_factor;
	float read_noise = (noise(uv * resolution.y * 0.5, 1.23 + TIME) - 0.5)
		* noise_intensity * min(noise_amplifier * 0.01, max_noise);
	// Grain is added after lens resampling, so AA/render scaling cannot erase it.
	// Like the old Fears to Fathom pass, use one luminance sample for all RGB.
	// Sum independent samples for a softer, bell-shaped distribution; continuous
	// coordinates remove the previous large square cells; no frame accumulation.
	float grain_frame = floor(TIME * 60.0);
	vec2 grain_uv = SCREEN_UV * resolution / max(resolution.y / 720.0, 0.5) / grain_size;
	vec2 first = hash22(grain_uv, grain_frame);
	vec2 second = hash22(grain_uv + vec2(17.31, 43.17), grain_frame + 5.19);
	float fine_grain = (first.x + first.y + second.x + second.y) * 0.5;
	float soft_grain = (noise(grain_uv * 0.8, grain_frame + 3.0) - 0.5) * 2.0;
	float grain = (fine_grain * 0.7 + soft_grain * 0.3) * sensor_grain;
	// Sensor texture must not turn a completely unlit room grey.
	float grain_mask = smoothstep(0.0, 0.035, max(luminance, 0.0));
	grain_mask *= mix(1.0, 0.7, smoothstep(0.15, 0.85, luminance)) * mix(0.25, 1.0, lens_amount);
	pixel_color.rgb = max(vec3(0.0), pixel_color.rgb + vec3(read_noise + grain) * grain_mask);
	// The opaque lens rim covers grain as well as the scene.
	float scanline = sin(SCREEN_UV.y * resolution.y * 3.14159265);
	pixel_color.rgb *= 1.0 - (0.5 + 0.5 * scanline) * 0.035 * vhs_strength * lens_amount;
	pixel_color.rgb *= 1.0 - vignette * vignette_strength;
	COLOR = pixel_color;
}
