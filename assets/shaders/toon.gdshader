// Opaque toon surface: cel bands, rim, optional emission and vertex colors.
// Primitives.material() / ArtKit.toon_material() build cached instances.
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

#include "res://assets/shaders/toon_common.gdshaderinc"
