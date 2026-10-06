extends TestCase


func test_tuning_levels_ascend() -> void:
	assert_lt(Tuning.WATCHED_AT, Tuning.SUSPECTED_AT)
	assert_lt(Tuning.SUSPECTED_AT, Tuning.WANTED_AT)
	assert_lt(Tuning.WANTED_AT, Tuning.HEAT_MAX)


func test_ladder_has_six_rungs() -> void:
	assert_eq(Tuning.CASINOS.size(), 6)
	assert_eq(Tuning.CASINOS[0]["id"], &"apex")


func test_can_await_frames() -> void:
	await tree.process_frame
	assert_not_null(tree.root)
