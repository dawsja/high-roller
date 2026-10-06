class_name MonitorOnStand
extends Node3D
## A Screen3D on a pole with a round foot (odds and payout monitors beside a
## game). Feet at the origin, the screen faces +Z, its centre `height` up.

var screen: Screen3D
var height: float = 1.0
var pole: MeshInstance3D
var foot: MeshInstance3D


func setup(screen_size: Vector2 = Vector2(0.56, 0.34), p_height: float = 1.0, line_count: int = 2,
		glow: Color = Color("8c4dff"), pole_color: Color = DiegeticKit.BEZEL, tilt_degrees: float = 8.0) -> MonitorOnStand:
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()
	height = maxf(p_height, screen_size.y * 0.5 + 0.05)
	if name == "":
		name = "Monitor"
	var pole_top := height - screen_size.y * 0.25
	foot = Primitives.rounded_cylinder(maxf(0.09, screen_size.x * 0.22), 0.035, pole_color.lightened(0.08), 0.012, 20)
	foot.name = "Foot"
	foot.position.y = 0.0175
	add_child(foot)
	pole = Primitives.rounded_cylinder(0.022, pole_top, pole_color, 0.008, 12)
	pole.name = "Pole"
	pole.position = Vector3(0.0, pole_top * 0.5, -0.03)
	add_child(pole)
	var mount := Node3D.new()
	mount.name = "Mount"
	mount.position = Vector3(0.0, height, 0.0)
	mount.rotation.x = -deg_to_rad(tilt_degrees)
	add_child(mount)
	screen = Screen3D.new()
	screen.name = "Screen"
	screen.setup(screen_size, line_count, glow)
	mount.add_child(screen)
	return self


func set_lines(entries: Array) -> void:
	if screen != null:
		screen.set_lines(entries)
