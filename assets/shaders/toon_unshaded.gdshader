// Flat, unlit toon color (plus emission): decals, indicator lights.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

#define TOON_UNSHADED
#include "res://assets/shaders/toon_common.gdshaderinc"
