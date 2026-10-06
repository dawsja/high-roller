class_name TestCase
extends RefCounted
## Base class for tests. Methods named test_* run in file order. A test may
## `await` (e.g. `await tree.process_frame`) — the runner awaits every test.

## The running SceneTree, for tests that need nodes, frames or physics.
var tree: SceneTree

var _failures: Array[String] = []


func before_each() -> void:
	pass


func after_each() -> void:
	pass


func fail(msg: String) -> void:
	var stack := get_stack()
	var where := ""
	for frame in stack:
		if str(frame.get("source", "")).ends_with("test_case.gd"):
			continue
		where = "%s:%d" % [str(frame.get("source", "")).get_file(), int(frame.get("line", 0))]
		break
	_failures.append("%s %s" % [where, msg])


func assert_true(cond: bool, msg: String = "") -> void:
	if not cond:
		fail("expected true. %s" % msg)


func assert_false(cond: bool, msg: String = "") -> void:
	if cond:
		fail("expected false. %s" % msg)


func assert_eq(actual: Variant, expected: Variant, msg: String = "") -> void:
	if typeof(actual) != typeof(expected) and not (_is_num(actual) and _is_num(expected)):
		fail("expected %s (%s), got %s (%s). %s" % [str(expected), type_string(typeof(expected)), str(actual), type_string(typeof(actual)), msg])
	elif actual != expected:
		fail("expected %s, got %s. %s" % [str(expected), str(actual), msg])


func assert_ne(actual: Variant, unexpected: Variant, msg: String = "") -> void:
	if typeof(actual) == typeof(unexpected) and actual == unexpected:
		fail("expected anything but %s. %s" % [str(unexpected), msg])


func assert_almost_eq(actual: float, expected: float, eps: float = 0.001, msg: String = "") -> void:
	if absf(actual - expected) > eps:
		fail("expected %f ± %f, got %f. %s" % [expected, eps, actual, msg])


func assert_gt(actual: float, bound: float, msg: String = "") -> void:
	if not actual > bound:
		fail("expected %s > %s. %s" % [str(actual), str(bound), msg])


func assert_gte(actual: float, bound: float, msg: String = "") -> void:
	if not actual >= bound:
		fail("expected %s >= %s. %s" % [str(actual), str(bound), msg])


func assert_lt(actual: float, bound: float, msg: String = "") -> void:
	if not actual < bound:
		fail("expected %s < %s. %s" % [str(actual), str(bound), msg])


func assert_lte(actual: float, bound: float, msg: String = "") -> void:
	if not actual <= bound:
		fail("expected %s <= %s. %s" % [str(actual), str(bound), msg])


func assert_between(actual: float, low: float, high: float, msg: String = "") -> void:
	if actual < low or actual > high:
		fail("expected %s in [%s, %s]. %s" % [str(actual), str(low), str(high), msg])


func assert_null(value: Variant, msg: String = "") -> void:
	if value != null:
		fail("expected null, got %s. %s" % [str(value), msg])


func assert_not_null(value: Variant, msg: String = "") -> void:
	if value == null:
		fail("expected non-null. %s" % msg)


func assert_has(container: Variant, item: Variant, msg: String = "") -> void:
	if not container.has(item):
		fail("expected %s to contain %s. %s" % [str(container), str(item), msg])


func _is_num(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT
