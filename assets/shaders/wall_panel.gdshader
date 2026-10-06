// Patterned wall / ceiling panels, projected in world space (the plane is
// picked from the surface normal, so boxes of any size line up). Lines can
// glow like neon piping. A darker dado below a rail breaks up tall walls.
// Patterns: 0 diamonds, 1 inset squares, 2 zigzag chevrons, 3 pinstripes.
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

#define TOON_SOFT 0.3
#define TOON_FLOOR 0.42
#define TOON_MID 0.78
#include "res://assets/shaders/toon_light.gdshaderinc"
#include "res://assets/shaders/pattern_util.gdshaderinc"

uniform vec4 color_base : source_color = vec4(0.165, 0.086, 0.251, 1.0);
uniform vec4 color_alt : source_color = vec4(0.231, 0.114, 0.369, 1.0);
uniform vec4 color_line : source_color = vec4(1.0, 0.247, 0.824, 1.0);
uniform int pattern : hint_enum("Diamonds", "Squares", "Zigzag", "Stripes") = 0;
// Metres per motif.
uniform float tile : hint_range(0.1, 8.0) = 0.9;
uniform float line_width : hint_range(0.0, 0.3) = 0.035;
// Emission on the lines (neon piping); 0 = painted lines.
uniform float line_glow : hint_range(0.0, 8.0) = 0.0;
// Rail height above floor_y (metres; negative = no rail) and the dado below it.
uniform float floor_y = 0.0;
uniform float rail_height = 1.1;
uniform float rail_width : hint_range(0.0, 0.3) = 0.05;
uniform float dado_shade : hint_range(0.0, 1.0) = 0.72;
uniform float base_glow : hint_range(0.0, 1.0) = 0.03;

varying vec3 v_world;
varying vec3 v_world_normal;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	vec3 n = abs(normalize(v_world_normal));
	vec2 uvw;
	if (n.y > 0.6) {
		uvw = v_world.xz;
	} else if (n.x > n.z) {
		uvw = v_world.zy;
	} else {
		uvw = v_world.xy;
	}
	vec2 p = uvw / tile;
	float w = max(length(fwidth(p)) * 0.7, 0.0005);
	float lw = line_width / tile;
	vec3 c;
	float line = 0.0;
	if (pattern == 1) {
		vec2 cell = floor(p);
		vec2 f = fract(p) - 0.5;
		float chk = mod(cell.x + cell.y, 2.0);
		c = mix(color_base.rgb, color_alt.rgb, chk);
		float b = max(abs(f.x), abs(f.y));
		line = fill(abs(b - 0.3) - lw * 0.5, w);
		c = mix(c, color_base.rgb * 0.62, fill(0.5 - b - lw * 0.35, w));
	} else if (pattern == 2) {
		float z = p.y + abs(fract(p.x) - 0.5);
		float band = fract(z * 2.0);
		c = mix(color_base.rgb, color_alt.rgb, mod(floor(z * 2.0), 2.0));
		float dz = min(band, 1.0 - band) * 0.5 * 0.7071;
		line = fill(dz - lw * 0.5, w);
	} else if (pattern == 3) {
		float sx = fract(p.x * 2.0);
		c = mix(color_base.rgb, color_alt.rgb, step(0.5, sx) * 0.6);
		float dx = min(abs(sx - 0.5), min(sx, 1.0 - sx)) * 0.5;
		line = fill(dx - lw * 0.35, w);
	} else {
		vec2 d = vec2(p.x + p.y, p.y - p.x) * 0.70710678;
		vec2 cell = floor(d);
		float chk = mod(cell.x + cell.y, 2.0);
		c = mix(color_base.rgb, color_alt.rgb, chk);
		vec2 g = abs(fract(d) - 0.5);
		line = fill(0.5 - max(g.x, g.y) - lw * 0.5, w);
		line = max(line, fill(length(fract(d) - 0.5) - lw * 1.3, w) * chk);
	}
	if (rail_height >= 0.0) {
		float y = v_world.y - floor_y;
		float wy = max(fwidth(y), 0.0005);
		c *= mix(dado_shade, 1.0, smoothstep(rail_height - wy, rail_height + wy, y));
		line = max(line, fill(abs(y - rail_height) - rail_width * 0.5, wy) * (n.y > 0.6 ? 0.0 : 1.0));
	}
	vec3 avg = mix(color_base.rgb, color_alt.rgb, 0.5);
	float far = smoothstep(0.12, 0.45, w);
	c = mix(c, avg, far);
	line *= 1.0 - far;
	c = mix(c, color_line.rgb, line);
	ALBEDO = c;
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
	EMISSION = c * base_glow + color_line.rgb * line * line_glow;
}
