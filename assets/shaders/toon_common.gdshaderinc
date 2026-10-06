// Body of the toon material family (toon, toon_alpha, toon_unshaded,
// toon_unshaded_alpha). The including shader sets render_mode and may define
// TOON_ALPHA (writes ALPHA) and TOON_UNSHADED (no lighting, no rim).

group_uniforms surface;
uniform vec4 albedo : source_color = vec4(1.0);
// Multiply albedo by the mesh's vertex colors.
uniform bool use_vertex_color = false;
// Self-lit amount: emission = albedo * emission_tint * emission_strength.
uniform float emission_strength : hint_range(0.0, 16.0) = 0.0;
uniform vec4 emission_tint : source_color = vec4(1.0);
// Soft fresnel rim that makes silhouettes pop against dark rooms.
uniform float rim_strength : hint_range(0.0, 2.0) = 0.3;
uniform float rim_width : hint_range(0.0, 1.0) = 0.42;
uniform vec4 rim_tint : source_color = vec4(1.0, 0.9, 1.0, 1.0);
// Brightens up-facing surfaces a little (cheap sky fill on top of the flat ambient).
uniform float top_fill : hint_range(0.0, 1.0) = 0.1;
// Extra self-light while the instance is hovered (outline_hover = 1).
uniform float hover_lift : hint_range(0.0, 1.0) = 0.14;
group_uniforms;

// Shared with the outline pass: ArtKit.set_outline_hover() sets it per instance.
instance uniform float outline_hover = 0.0;

#ifndef TOON_UNSHADED
#include "res://assets/shaders/toon_light.gdshaderinc"
#endif

void fragment() {
	vec4 c = albedo;
	if (use_vertex_color) {
		c *= COLOR;
	}
#ifdef TOON_ALPHA
	ALPHA = c.a;
#endif
	vec3 glow = c.rgb * emission_tint.rgb * emission_strength + c.rgb * hover_lift * outline_hover;
#ifdef TOON_UNSHADED
	ALBEDO = c.rgb + glow;
#else
	ALBEDO = c.rgb;
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
	float fres = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = smoothstep(1.0 - rim_width, 1.0 - rim_width * 0.35, fres);
	vec3 world_n = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	float top = clamp(world_n.y * 0.5 + 0.5, 0.0, 1.0);
	EMISSION = glow + mix(c.rgb, rim_tint.rgb, 0.55) * rim * rim_strength + c.rgb * top * top_fill;
#endif
}
