// Flat, unlit, see-through color: highlight rings, vision cones, overlays.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_opaque, shadows_disabled;

#define TOON_UNSHADED
#define TOON_ALPHA
#include "res://assets/shaders/toon_common.gdshaderinc"
