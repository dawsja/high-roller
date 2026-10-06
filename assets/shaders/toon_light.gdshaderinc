// Shared cel lighting for every lit High Roller surface: three light bands
// (shadow, mid, lit) with soft edges, plus an optional toon specular blob.
// Define TOON_SOFT / TOON_FLOOR / TOON_MID / TOON_GLOSS before including to
// change a shader's defaults (floors use wide, soft bands).

#ifndef TOON_SOFT
#define TOON_SOFT 0.035
#endif
#ifndef TOON_FLOOR
#define TOON_FLOOR 0.34
#endif
#ifndef TOON_MID
#define TOON_MID 0.7
#endif
#ifndef TOON_GLOSS
#define TOON_GLOSS 0.0
#endif

group_uniforms cel_light;
// Darkest band (surfaces facing away from a light still get this much of it).
uniform float shade_floor : hint_range(0.0, 1.0) = TOON_FLOOR;
// Middle band level.
uniform float shade_mid : hint_range(0.0, 1.0) = TOON_MID;
// N.L where the shadow band turns into the mid band, and mid into lit.
uniform float band_low : hint_range(-1.0, 1.0) = -0.05;
uniform float band_high : hint_range(-1.0, 1.0) = 0.45;
// Half width of each band edge (0 = hard cel edge).
uniform float band_soft : hint_range(0.001, 0.6) = TOON_SOFT;
// Toon highlight strength and size (0 = no highlight).
uniform float gloss : hint_range(0.0, 2.0) = TOON_GLOSS;
uniform float gloss_size : hint_range(0.0, 1.0) = 0.3;
group_uniforms;

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lo = smoothstep(band_low - band_soft, band_low + band_soft, ndl);
	float hi = smoothstep(band_high - band_soft, band_high + band_soft, ndl);
	float level = mix(mix(shade_floor, shade_mid, lo), 1.0, hi);
	// LIGHT_COLOR carries a factor of PI (Godot's PBR convention).
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * level * (1.0 / PI);
	if (gloss > 0.0) {
		vec3 h = normalize(LIGHT + VIEW);
		float nh = max(dot(NORMAL, h), 0.0);
		float cut = 1.0 - 0.1 * gloss_size;
		float s = smoothstep(cut - 0.006, cut + 0.006, nh) * step(0.0, ndl);
		SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * s * gloss * (1.0 / PI);
	}
}
