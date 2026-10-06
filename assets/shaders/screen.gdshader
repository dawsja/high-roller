// A machine's monitor glass: dark emissive panel with faint scanlines, a
// glowing edge and an optional texture (e.g. a SubViewport) shown on it.
// Expects 0..1 UVs across the face (QuadMesh, or a MeshFactory rounded_box face).
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque, shadows_disabled;

uniform vec4 screen_color : source_color = vec4(0.035, 0.02, 0.07, 1.0);
uniform vec4 glow_color : source_color = vec4(0.55, 0.3, 1.0, 1.0);
uniform float brightness : hint_range(0.0, 4.0) = 1.0;
uniform float edge_glow : hint_range(0.0, 2.0) = 0.35;
uniform float scanlines : hint_range(0.0, 1.0) = 0.12;
uniform float scanline_count = 120.0;
// Slow bright band that rolls down the glass (0 = off).
uniform float sheen : hint_range(0.0, 1.0) = 0.06;
uniform bool use_texture = false;
uniform sampler2D screen_texture : source_color, hint_default_black, filter_linear_mipmap;
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);

void fragment() {
	vec2 uv = UV * uv_scale + uv_offset;
	vec3 c = screen_color.rgb;
	if (use_texture) {
		vec4 t = texture(screen_texture, uv);
		c = mix(c, t.rgb, t.a);
	}
	float s = 0.5 + 0.5 * sin(uv.y * scanline_count * 6.28318);
	c *= 1.0 - scanlines * s;
	vec2 d = abs(UV - 0.5) * 2.0;
	float edge = smoothstep(0.72, 1.0, max(d.x, d.y));
	c += glow_color.rgb * edge * edge * edge_glow;
	float band = fract(UV.y * 0.6 - TIME * 0.07);
	c += glow_color.rgb * sheen * smoothstep(0.0, 0.08, band) * smoothstep(0.2, 0.08, band);
	ALBEDO = c * brightness;
}
