// See-through toon surface (albedo alpha < 1): glass, tints, highlight discs.
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque;

#define TOON_ALPHA
#include "res://assets/shaders/toon_common.gdshaderinc"
