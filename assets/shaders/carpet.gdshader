// Loud casino carpet, tiled in world XZ so any floor mesh lines up. Four
// palette colors drive it (ArtKit.carpet_material recolors per casino).
// Patterns: 0 eyes and swirls (night club), 1 stars and tumbling cards
// (sky casino), 2 confetti rings, triangles and squiggles.
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

#define TOON_SOFT 0.35
#define TOON_FLOOR 0.55
#define TOON_MID 0.8
#include "res://assets/shaders/toon_light.gdshaderinc"
#include "res://assets/shaders/pattern_util.gdshaderinc"

uniform vec4 color_base : source_color = vec4(0.09, 0.07, 0.24, 1.0);
uniform vec4 color_1 : source_color = vec4(1.0, 0.54, 0.24, 1.0);
uniform vec4 color_2 : source_color = vec4(0.86, 0.16, 0.32, 1.0);
uniform vec4 color_3 : source_color = vec4(1.0, 0.82, 0.25, 1.0);
uniform int pattern : hint_enum("Eyes", "Stars", "Confetti") = 0;
// Metres per motif.
uniform float tile : hint_range(0.2, 8.0) = 1.3;
uniform float rotation = 0.0;
// Use the mesh UVs (times uv_scale) instead of world XZ.
uniform bool use_uv = false;
uniform float uv_scale = 4.0;
// Floors sit a little darker than props so machines pop against them.
uniform float brightness : hint_range(0.0, 2.0) = 0.8;
// Self-light so the floor never goes dark under the cel bands.
uniform float base_glow : hint_range(0.0, 1.0) = 0.04;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec3 carpet_eyes(vec2 p, float w) {
	vec3 c = color_base.rgb;
	// Confetti dots along the gaps between rows of eyes.
	vec2 dp = p - vec2(0.25, 0.0);
	vec2 dcell = floor(vec2(dp.x * 2.0, dp.y + 0.5));
	vec2 dl = vec2((fract(dp.x * 2.0) - 0.5) * 0.5, fract(dp.y + 0.5) - 0.5);
	float dh = hash12(dcell + 31.0);
	c = mix(c, dh < 0.5 ? color_3.rgb : color_1.rgb, fill(length(dl) - 0.045, w) * step(0.25, dh));

	vec2 q = p;
	float row = floor(q.y);
	q.x += 0.5 * mod(row, 2.0);
	vec2 cell = floor(q);
	vec2 e = fract(q) - 0.5 - (hash22(cell) - 0.5) * 0.08;
	float h = hash12(cell + 17.0);
	float r = length(e);
	float ang = atan(e.y, e.x);
	if (h < 0.7) {
		float big = mix(0.29, 0.35, fract(h * 13.7));
		// A swoosh arc hugging part of the eye.
		float arc = fill(abs(r - big - 0.07) - 0.025, w) * step(0.55, fract(ang / 6.28318 + h * 5.0));
		c = mix(c, color_3.rgb, arc);
		c = mix(c, color_1.rgb, fill(r - big, w));
		c = mix(c, color_2.rgb, fill(r - big * 0.7, w));
		vec2 look = vec2(cos(h * 41.0), sin(h * 41.0)) * big * 0.17;
		c = mix(c, color_base.rgb * 0.4, fill(length(e - look) - big * 0.36, w));
		c = mix(c, mix(color_3.rgb, vec3(1.0), 0.6), fill(length(e - look - vec2(-0.3, 0.3) * big * 0.4) - big * 0.1, w));
	} else {
		float s = fract(ang / 6.28318 - r * 2.6 + h * 4.0);
		float band = fill(abs(s - 0.5) - 0.2, max(w * 4.0, 0.04)) * fill(r - 0.36, w) * smoothstep(0.03, 0.09, r);
		c = mix(c, color_3.rgb, band);
		c = mix(c, color_1.rgb, fill(r - 0.08, w));
	}
	return c;
}

vec3 carpet_stars(vec2 p, float w) {
	vec3 c = color_base.rgb;
	// Speckles.
	vec2 sp = p * 3.0;
	vec2 sc = floor(sp);
	float sh = hash12(sc + 3.1);
	vec2 so = (hash22(sc + 9.2) - 0.5) * 0.6;
	c = mix(c, mix(color_3.rgb, color_1.rgb, step(0.85, sh)), fill(length(fract(sp) - 0.5 - so) - 0.06, w * 3.0) * step(0.6, sh));
	vec2 cell = floor(p);
	vec2 f = fract(p) - 0.5;
	float h = hash12(cell);
	if (h < 0.5) {
		vec2 o = (hash22(cell + 5.0) - 0.5) * 0.18;
		vec2 cp = rot2(h * 40.0) * (f - o);
		float card = sd_round_box(cp, vec2(0.16, 0.23), 0.04);
		c = mix(c, color_base.rgb * 0.55, fill(card - 0.025, w));
		c = mix(c, color_1.rgb, fill(card, w));
		c = mix(c, mix(color_1.rgb, vec3(1.0), 0.55), fill(card + 0.03, w));
		float pip = abs(cp.x) * 1.4 + abs(cp.y) - 0.085;
		c = mix(c, color_2.rgb, fill(pip, w));
	} else {
		vec2 o = (hash22(cell + 2.0) - 0.5) * 0.36;
		float r = mix(0.07, 0.17, fract(h * 9.1));
		vec2 q = rot2(h * 20.0) * (f - o);
		c = mix(c, color_3.rgb, fill(sd_star5(q, r, 0.45), w));
	}
	return c;
}

vec3 carpet_confetti(vec2 p, float w) {
	vec3 c = color_base.rgb;
	for (int i = 0; i < 2; i++) {
		float k = i == 0 ? 1.0 : 1.7;
		vec2 lp = p * k + float(i) * vec2(0.37, 0.61);
		vec2 cell = floor(lp);
		float h = hash12(cell + float(i) * 13.0);
		vec2 o = (hash22(cell + 7.0) - 0.5) * 0.3;
		vec2 q = rot2(h * 30.0) * (fract(lp) - 0.5 - o);
		float lw = w * k;
		vec3 col = h < 0.33 ? color_1.rgb : (h < 0.66 ? color_2.rgb : color_3.rgb);
		float kind = fract(h * 7.0);
		float d;
		if (kind < 0.33) {
			d = abs(length(q) - 0.15) - 0.045;
		} else if (kind < 0.66) {
			d = sd_triangle(q, 0.13);
		} else {
			d = max(abs(q.y - 0.05 * sin(q.x * 24.0)) - 0.035, abs(q.x) - 0.2);
		}
		c = mix(c, col, fill(d, lw));
	}
	return c;
}

void fragment() {
	vec2 p = use_uv ? UV * uv_scale : v_world.xz / tile;
	p = rot2(rotation) * p;
	float w = max(length(fwidth(p)) * 0.7, 0.0005);
	vec3 c;
	if (pattern == 1) {
		c = carpet_stars(p, w);
	} else if (pattern == 2) {
		c = carpet_confetti(p, w);
	} else {
		c = carpet_eyes(p, w);
	}
	// Far away the motifs would shimmer: settle toward their average color.
	vec3 avg = mix(color_base.rgb, (color_1.rgb + color_2.rgb + color_3.rgb) / 3.0, 0.3);
	c = mix(c, avg, smoothstep(0.1, 0.4, w)) * brightness;
	ALBEDO = c;
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
	EMISSION = c * base_glow;
}
