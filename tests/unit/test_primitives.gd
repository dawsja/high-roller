extends TestCase


func test_materials_are_cached_per_color() -> void:
	assert_true(Primitives.material(Color.RED) == Primitives.material(Color.RED))
	assert_false(Primitives.material(Color.RED) == Primitives.material(Color.BLUE))


func test_static_box_has_collision_on_layer() -> void:
	var body := Primitives.static_box(Vector3(2, 1, 2), Color.GRAY, 1 << 4)
	assert_eq(body.collision_layer, 16)
	assert_eq(body.get_child_count(), 2)
	body.free()
