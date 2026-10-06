extends TestCase

## The contract list from docs/ARCHITECTURE.md (World layer, InputSetup).
const CONTRACT := [
	&"move_forward", &"move_back", &"move_left", &"move_right", &"run", &"jump", &"dive",
	&"interact", &"tackle", &"throw_chips", &"knock_over", &"pause", &"toggle_debug",
	&"ui_quiz_1", &"ui_quiz_2", &"ui_quiz_3",
]


func _has_key(action: StringName, code: Key) -> bool:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == code:
			return true
	return false


func _count(action: StringName, type: String) -> int:
	var n := 0
	for event: InputEvent in InputMap.action_get_events(action):
		if event.is_class(type):
			n += 1
	return n


func test_defines_every_contract_action() -> void:
	InputSetup.ensure_actions()
	for action: StringName in CONTRACT:
		assert_true(InputMap.has_action(action), String(action))
		assert_has(InputSetup.ACTIONS, action)
		assert_gt(_count(action, "InputEventKey"), 0, "%s has a key" % action)
		assert_gt(_count(action, "InputEventJoypadButton") + _count(action, "InputEventJoypadMotion"), 0, "%s has a gamepad binding" % action)


func test_is_idempotent() -> void:
	InputSetup.ensure_actions()
	var before: Dictionary = {}
	for action: StringName in InputSetup.ACTIONS:
		before[action] = InputMap.action_get_events(action).size()
	InputSetup.ensure_actions()
	InputSetup.ensure_actions()
	for action: StringName in InputSetup.ACTIONS:
		assert_eq(InputMap.action_get_events(action).size(), before[action], String(action))


func test_restores_a_missing_binding() -> void:
	InputSetup.ensure_actions()
	var count := InputMap.action_get_events(&"jump").size()
	InputMap.action_erase_events(&"jump")
	InputSetup.ensure_actions()
	assert_eq(InputMap.action_get_events(&"jump").size(), count)


func test_contract_keys() -> void:
	InputSetup.ensure_actions()
	var expected := {
		&"move_forward": [KEY_W, KEY_UP], &"move_back": [KEY_S, KEY_DOWN],
		&"move_left": [KEY_A, KEY_LEFT], &"move_right": [KEY_D, KEY_RIGHT],
		&"run": [KEY_SHIFT], &"jump": [KEY_SPACE], &"dive": [KEY_CTRL], &"interact": [KEY_E],
		&"tackle": [KEY_F], &"throw_chips": [KEY_G], &"knock_over": [KEY_Q], &"pause": [KEY_ESCAPE],
		&"toggle_debug": [KEY_F3], &"ui_quiz_1": [KEY_1], &"ui_quiz_2": [KEY_2], &"ui_quiz_3": [KEY_3],
	}
	for action: StringName in expected:
		for code: Key in expected[action]:
			assert_true(_has_key(action, code), "%s bound to %s" % [action, OS.get_keycode_string(code)])


func test_move_actions_use_the_left_stick() -> void:
	InputSetup.ensure_actions()
	assert_eq(_count(&"move_forward", "InputEventJoypadMotion"), 1)
	assert_almost_eq(InputMap.action_get_deadzone(&"move_left"), Tuning.INPUT_STICK_DEADZONE)
	var press := InputEventKey.new()
	press.physical_keycode = KEY_E
	press.pressed = true
	assert_true(press.is_action(&"interact"))
	assert_false(press.is_action(&"jump"))
