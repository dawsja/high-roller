class_name InputSetup
extends RefCounted
## Registers every gameplay input action in code (project.godot has no
## InputMap). ensure_actions() is idempotent: it only adds what is missing,
## so call it from anything that reads input (main, the player, tests).

const ACTIONS: Array[StringName] = [
	&"move_forward", &"move_back", &"move_left", &"move_right",
	&"run", &"jump", &"dive", &"interact", &"tackle", &"throw_chips", &"knock_over",
	&"pause", &"toggle_debug", &"ui_quiz_1", &"ui_quiz_2", &"ui_quiz_3",
]

const MOVE_ACTIONS: Array[StringName] = [&"move_forward", &"move_back", &"move_left", &"move_right"]


static func ensure_actions() -> void:
	var map := bindings()
	for action: StringName in ACTIONS:
		if not InputMap.has_action(action):
			var deadzone := Tuning.INPUT_STICK_DEADZONE if MOVE_ACTIONS.has(action) else Tuning.INPUT_BUTTON_DEADZONE
			InputMap.add_action(action, deadzone)
		for event: InputEvent in map[action]:
			if not InputMap.action_has_event(action, event):
				InputMap.action_add_event(action, event)


## Default bindings: action -> Array of fresh InputEvents. Keyboard keys are
## physical (layout independent); gamepad events match any controller.
## Gamepad: left stick moves, A jump, B dive, X interact, Y throw chips,
## LB / left stick click run, RB tackle, RT knock over, Start pause,
## Back debug, d-pad left/up/right answer the ID quiz.
static func bindings() -> Dictionary:
	return {
		&"move_forward": [_key(KEY_W), _key(KEY_UP), _axis(JOY_AXIS_LEFT_Y, -1.0)],
		&"move_back": [_key(KEY_S), _key(KEY_DOWN), _axis(JOY_AXIS_LEFT_Y, 1.0)],
		&"move_left": [_key(KEY_A), _key(KEY_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0)],
		&"move_right": [_key(KEY_D), _key(KEY_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0)],
		&"run": [_key(KEY_SHIFT), _button(JOY_BUTTON_LEFT_SHOULDER), _button(JOY_BUTTON_LEFT_STICK)],
		&"jump": [_key(KEY_SPACE), _button(JOY_BUTTON_A)],
		&"dive": [_key(KEY_CTRL), _button(JOY_BUTTON_B)],
		&"interact": [_key(KEY_E), _button(JOY_BUTTON_X)],
		&"tackle": [_key(KEY_F), _button(JOY_BUTTON_RIGHT_SHOULDER)],
		&"throw_chips": [_key(KEY_G), _button(JOY_BUTTON_Y)],
		&"knock_over": [_key(KEY_Q), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)],
		&"pause": [_key(KEY_ESCAPE), _button(JOY_BUTTON_START)],
		&"toggle_debug": [_key(KEY_F3), _button(JOY_BUTTON_BACK)],
		&"ui_quiz_1": [_key(KEY_1), _key(KEY_KP_1), _button(JOY_BUTTON_DPAD_LEFT)],
		&"ui_quiz_2": [_key(KEY_2), _key(KEY_KP_2), _button(JOY_BUTTON_DPAD_UP)],
		&"ui_quiz_3": [_key(KEY_3), _key(KEY_KP_3), _button(JOY_BUTTON_DPAD_RIGHT)],
	}


static func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.device = -1
	return event


static func _button(button: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.device = -1
	return event


static func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	event.device = -1
	return event
