// Inverted-hull outline, used as the next_pass of toon materials. The hull
// grows in view space by a fixed number of pixels (at a 900 px tall
// reference viewport, so it scales with resolution), thinning a little far
// away. Per-instance uniforms (shared with the toon pass) switch it to a
// bright glowing hover outline and pick how hard-edged meshes grow.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, shadows_disabled;

uniform vec4 outline_color : source_color = vec4(0.110, 0.059, 0.180, 1.0);
// Width in pixels at 900 px viewport height.
uniform float outline_width : hint_range(0.0, 12.0) = 2.6;
// Hovered width and brightness (HDR, so it blooms), and a gentle pulse.
uniform float hover_width : hint_range(0.0, 16.0) = 6.0;
uniform float hover_energy : hint_range(0.0, 8.0) = 1.8;
uniform float hover_pulse : hint_range(0.0, 1.0) = 0.15;
// Outlines thin from full width at fade_start metres to far_scale at fade_end.
uniform float fade_start = 7.0;
uniform float fade_end = 28.0;
uniform float far_scale : hint_range(0.0, 1.0) = 0.45;

// 0..1: hovered (ArtKit.set_outline_hover).
instance uniform float outline_hover = 0.0;
instance uniform vec4 outline_hover_color : source_color = vec4(1.0, 0.94, 0.42, 1.0);
// How the hull grows: 0 along normals (smooth meshes), 1 per axis away from
// the origin (boxes, prisms), 2 radially in XZ and per axis in Y (cylinders).
// Hard-edged meshes split their normals at edges, which tears a normal hull.
instance uniform float outline_mode = 0.0;

void vertex() {
	vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 dir;
	if (outline_mode > 1.5) {
		vec2 xz = VERTEX.xz;
		float l = length(xz);
		vec2 rad = l > 0.00001 ? xz / l : vec2(0.0);
		vec3 scl = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
		dir = mat3(MODELVIEW_MATRIX) * (vec3(rad.x, sign(VERTEX.y), rad.y) / max(scl, vec3(0.0001)));
	} else if (outline_mode > 0.5) {
		vec3 scl = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
		dir = mat3(MODELVIEW_MATRIX) * (sign(VERTEX) / max(scl, vec3(0.0001)));
	} else {
		dir = normalize(MODELVIEW_NORMAL_MATRIX * NORMAL);
	}
	float depth = max(-vp.z, 0.02);
	// Metres per pixel here: project a 1 m vertical step (works for any
	// projection; reading PROJECTION_MATRIX elements in vertex() returns 0 on
	// the Compatibility renderer).
	vec4 c0 = PROJECTION_MATRIX * vp;
	vec4 c1 = PROJECTION_MATRIX * (vp + vec4(0.0, 1.0, 0.0, 0.0));
	float w0 = max(abs(c0.w), 0.0001);
	float w1 = max(abs(c1.w), 0.0001);
	float ndc_per_m = abs(c1.y / w1 - c0.y / w0);
	float px = 2.0 / max(ndc_per_m * 900.0, 0.0001);
	float far = mix(1.0, far_scale, smoothstep(fade_start, fade_end, depth));
	float pulse = 1.0 + hover_pulse * sin(TIME * 6.0) * outline_hover;
	float width = mix(outline_width * far, hover_width, outline_hover) * pulse;
	vp.xyz += dir * px * width;
	POSITION = PROJECTION_MATRIX * vp;
}

void fragment() {
	ALBEDO = mix(outline_color.rgb, outline_hover_color.rgb * hover_energy, outline_hover);
}
