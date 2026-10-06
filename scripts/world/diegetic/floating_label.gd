class_name FloatingLabel
extends Node3D
## The big floating game name over a machine ("SLOTS"): an ArtKit
## floating sign (Lilita One, thick dark outline, billboarded, gently
## bobbing, fading with camera distance), plus an optional smaller subtitle
## line under it.

var sign_label: Label3D
var subtitle: Label3D
var text: String = ""
var size: float = 0.34
## Long names shrink to stay within this width (m).
var max_width: float = 1.5


func setup(p_text: String, p_size: float = 0.34, color: Color = Color.WHITE, p_max_width: float = 1.5) -> FloatingLabel:
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()
	text = p_text
	size = maxf(p_size, 0.05)
	max_width = p_max_width
	if name == "":
		name = "FloatingLabel"
	sign_label = ArtKit.floating_sign(p_text.to_upper(), size, color)
	add_child(sign_label)
	_fit()
	return self


func set_text(p_text: String) -> void:
	text = p_text
	if sign_label != null:
		sign_label.text = p_text.to_upper()
		_fit()


## Width of the name as shown (m).
func get_width() -> float:
	return DiegeticKit.text_width(sign_label, sign_label.text, sign_label.pixel_size) if sign_label != null else 0.0


func _fit() -> void:
	var px := DiegeticKit.pixel_size_for(size, sign_label.font_size)
	var w := DiegeticKit.text_width(sign_label, sign_label.text, px)
	if max_width > 0.0 and w > max_width:
		px *= max_width / w
	sign_label.pixel_size = px


func get_text() -> String:
	return sign_label.text if sign_label != null else ""


## A smaller line under the name ("CLOSED", "Min $10"); "" hides it.
func set_subtitle(p_text: String, color: Color = DiegeticKit.TEXT_WHITE) -> void:
	if subtitle == null:
		subtitle = ArtKit.make_label("", size * 0.0045, color, 64, true)
		subtitle.name = "Subtitle"
		subtitle.position.y = -size * 0.95
		add_child(subtitle)
	subtitle.text = p_text
	subtitle.modulate = color
	subtitle.visible = p_text != ""
