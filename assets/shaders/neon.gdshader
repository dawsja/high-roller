// Neon tube / sign glow: unlit, HDR-bright so world glow blooms it, with a
// whiter core where the tube faces the camera. Optional pulse and flicker.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.247, 0.824, 1.0);
// Brightness multiplier; above ~1.4 it blooms.
uniform float energy : hint_range(0.0, 16.0) = 2.0;
// How white-hot the camera-facing middle of a tube gets.
uniform float core : hint_range(0.0, 1.0) = 0.15;
// Slow breathing (radians per second, 0 = off) and its depth.
uniform float pulse_speed = 0.0;
uniform float pulse_depth : hint_range(0.0, 1.0) = 0.35;
// Chance-based dropouts like a tired sign (0 = steady).
uniform float flicker : hint_range(0.0, 1.0) = 0.0;
uniform float phase = 0.0;

// Per-instance dimmer for chasing bulbs and marquee animations (ArtKit.set_neon_level).
instance uniform float neon_level = 1.0;

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	vec3 c = mix(color.rgb, vec3(1.0), core * facing * facing);
	float k = neon_level;
	if (pulse_speed > 0.0) {
		k *= 1.0 - pulse_depth * (0.5 + 0.5 * sin(TIME * pulse_speed + phase));
	}
	if (flicker > 0.0) {
		float n = fract(sin(floor(TIME * 14.0 + phase * 7.0) * 91.73) * 43758.547);
		k *= 1.0 - 0.8 * step(1.0 - flicker * 0.5, n);
	}
	ALBEDO = c * energy * k;
}
