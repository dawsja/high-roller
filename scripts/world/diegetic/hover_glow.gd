class_name HoverGlow
extends RefCounted
## The "you can press this" look: the thick, pulsing, blooming yellow
## outline from ArtKit.set_outline_hover on every toon mesh under a node, plus
## a tiny scale pop. Cheap (per-instance uniforms, no new materials).

const POP_SCALE := 1.035
const POP_SECONDS := 0.09


## Turns the hover outline on or off for every mesh under `root`.
static func apply(root: Node, on: bool, color: Color = ArtKit.HOVER_COLOR) -> void:
	if root == null:
		return
	ArtKit.set_outline_hover(root, on, color)


static func is_on(root: Node) -> bool:
	return root != null and ArtKit.is_outline_hovered(root)


## apply() plus a quick scale pop of `root` (a Node3D) from its rest scale.
## Returns the tween (null outside the tree: the scale is set directly).
static func apply_with_pop(root: Node3D, on: bool, rest_scale: Vector3 = Vector3.ONE, color: Color = ArtKit.HOVER_COLOR) -> Tween:
	apply(root, on, color)
	if root == null:
		return null
	var target := rest_scale * (POP_SCALE if on else 1.0)
	if not root.is_inside_tree():
		root.scale = target
		return null
	var tw := root.create_tween()
	tw.tween_property(root, "scale", target, POP_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return tw
