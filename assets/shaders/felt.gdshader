// Table felt: base color with a subtle woven noise, darker toward the rim
// and an inset printed border line. Shapes come from object-space XZ, so set
// half_size to the felt's half extents (metres) in the mesh's own space.
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

#define TOON_SOFT 0.3
#define TOON_FLOOR 0.55
#define TOON_MID 0.8
#include "res://assets/shaders/toon_light.gdshaderinc"
#include "res://assets/shaders/pattern_util.gdshaderinc"

uniform vec4 felt_color : source_color = vec4(0.11, 0.56, 0.32, 1.0);
uniform vec4 border_color : source_color = vec4(1.0, 0.86, 0.4, 1.0);
uniform int shape : hint_enum("RoundRect", "Ellipse") = 0;
uniform vec2 half_size = vec2(0.5, 0.5);
uniform vec2 center = vec2(0.0, 0.0);
uniform float corner_radius : hint_range(0.0, 2.0) = 0.12;
// Border line: distance in from the edge, and its width (metres; 0 = none).
uniform float border_inset : hint_range(0.0, 1.0) = 0.07;
uniform float border_width : hint_range(0.0, 0.2) = 0.012;
uniform float noise_strength : hint_range(0.0, 0.5) = 0.07;
uniform float noise_scale = 70.0;
// Darkening toward the rim and how far in it reaches (metres).
uniform float edge_shade : hint_range(0.0, 1.0) = 0.25;
uniform float edge_reach : hint_range(0.01, 2.0) = 0.3;
uniform float base_glow : hint_range(0.0, 1.0) = 0.05;

varying vec2 v_local;

void vertex() {
	v_local = VERTEX.xz;
}

void fragment() {
	vec2 lp = v_local - center;
	float d;
	if (shape == 1) {
		// Cheap ellipse distance (exact on the axes, close enough for a print line).
		vec2 hs = max(half_size, vec2(0.001));
		float k = length(lp / hs);
		d = (k - 1.0) * min(hs.x, hs.y);
	} else {
		d = sd_round_box(lp, half_size, min(corner_radius, min(half_size.x, half_size.y)));
	}
	float w = max(fwidth(d), 0.0002);
	float n = value_noise(v_local * noise_scale) * 0.6 + value_noise(v_local * noise_scale * 2.7 + 11.0) * 0.4;
	vec3 c = felt_color.rgb * (1.0 + (n - 0.5) * noise_strength * 2.0);
	c *= 1.0 - edge_shade * smoothstep(-edge_reach, 0.0, d);
	if (border_width > 0.0) {
		float line = fill(abs(d + border_inset) - border_width * 0.5, w);
		c = mix(c, border_color.rgb, line);
	}
	ALBEDO = c;
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
	EMISSION = c * base_glow;
}
