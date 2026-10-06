class_name Perception
extends RefCounted
## Static sight / hearing / targeting checks for guards and cameras. Pure
## geometry: line of sight (walls) is the world's job, done after these pass.


## True if `target` is inside a vision cone at `origin` looking along `forward`.
## Works on the horizontal plane: heights are ignored, so a player jumping or
## a camera tilted down still counts by floor position. `fov_degrees` is the
## full cone angle (110 = 55 each side); edges and `max_range` are inclusive.
## A target exactly at the origin is always visible. A forward with no
## horizontal part (looking straight down) sees all around within range.
static func in_vision_cone(origin: Vector3, forward: Vector3, target: Vector3, fov_degrees: float, max_range: float) -> bool:
	var to_target := _flat(target - origin)
	if to_target.is_zero_approx():
		return true
	if to_target.length() > max_range:
		return false
	var flat_forward := _flat(forward)
	if flat_forward.is_zero_approx() or fov_degrees >= 360.0:
		return true
	var half_angle := deg_to_rad(clampf(fov_degrees, 0.0, 360.0) * 0.5)
	var cos_angle := flat_forward.normalized().dot(to_target.normalized())
	return cos_angle >= cos(half_angle) - 0.000001


## True if a noise at `noise_pos` reaches `listener` (3D distance, radius inclusive).
static func can_hear(listener: Vector3, noise_pos: Vector3, radius: float) -> bool:
	return listener.distance_to(noise_pos) <= radius


## pid with the most Heat in `known_heat` (pid -> Heat); ties go to the lowest
## pid; −1 when empty. NaN entries are skipped.
static func pick_target(known_heat: Dictionary) -> int:
	var best_pid := -1
	var best_heat := 0.0
	var found := false
	for key: Variant in known_heat:
		var pid := int(key)
		var heat := float(known_heat[key])
		if is_nan(heat):
			continue
		if not found or heat > best_heat or (heat == best_heat and pid < best_pid):
			best_pid = pid
			best_heat = heat
			found = true
	return best_pid


## Distance between two points on the horizontal plane (y ignored).
static func flat_distance(a: Vector3, b: Vector3) -> float:
	return _flat(b - a).length()


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
