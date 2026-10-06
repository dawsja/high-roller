extends TestCase
## FakeId (caps, flagging, burning, serialization), IdGenerator (names, dates,
## states, grades, determinism), IdQuiz (question shape, decoys, fairness) and
## Forger (rotation and signals).

const CHEAP := HR.IdGrade.CHEAP
const SOLID := HR.IdGrade.SOLID
const FLAWLESS := HR.IdGrade.FLAWLESS
const MONTH_RE := "(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)"

var _birthday_re := RegEx.create_from_string("^%s ([1-9]|[12][0-9]|3[01]), [0-9]{4}$" % MONTH_RE)


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _id(grade: int = CHEAP) -> FakeId:
	return FakeId.new("Chet Bonanza", "Mar 14, 1971", "Nevada", grade)


func _grade_cap(grade: int) -> int:
	return int(Tuning.ID_GRADES[grade]["cap"])


func _assert_birthday_format(text: String, msg: String = "") -> void:
	assert_not_null(_birthday_re.search(text), "birthday %s not like 'Mar 14, 1971'. %s" % [text, msg])
	assert_false(IdGenerator.parse_birthday(text).is_empty(), "birthday %s is not a real date. %s" % [text, msg])


func _assert_name_from_lists(full_name: String, msg: String = "") -> void:
	var parts := IdGenerator.split_name(full_name)
	assert_eq(parts.size(), 2, "name %s should be 'First Last'. %s" % [full_name, msg])
	if parts.size() == 2:
		assert_has(IdGenerator.FIRST_NAMES, parts[0], msg)
		assert_has(IdGenerator.LAST_NAMES, parts[1], msg)


# --- FakeId -----------------------------------------------------------------

func test_fake_id_cap_comes_from_grade() -> void:
	for grade: int in [CHEAP, SOLID, FLAWLESS]:
		var id := _id(grade)
		assert_eq(id.grade, grade)
		assert_eq(id.cap, _grade_cap(grade), "grade %d" % grade)
		assert_eq(id.banked_under, 0)
		assert_false(id.flagged)
		assert_false(id.burned)
		assert_true(id.passes_check(), "a fresh ID passes")
		assert_eq(id.grade_name(), str(Tuning.ID_GRADES[grade]["name"]))
		assert_almost_eq(id.spotted_chance(), float(Tuning.ID_GRADES[grade]["spotted_chance"]))


func test_fake_id_fields_stored() -> void:
	var id := _id()
	assert_eq(id.name, "Chet Bonanza")
	assert_eq(id.birthday, "Mar 14, 1971")
	assert_eq(id.home_state, "Nevada")
	assert_eq(id.describe(), "Chet Bonanza · Mar 14, 1971 · Nevada")


func test_fake_id_unknown_grade_counts_as_cheap() -> void:
	var id := FakeId.new("A B", "Jan 1, 1980", "Ohio", 99)
	assert_eq(id.grade, CHEAP)
	assert_eq(id.cap, _grade_cap(CHEAP))


func test_record_banked_under_cap_does_not_flag() -> void:
	var id := _id(CHEAP)
	assert_false(id.record_banked(1000))
	assert_false(id.record_banked(2000))
	assert_eq(id.banked_under, 3000)
	assert_false(id.flagged)
	assert_true(id.passes_check())
	assert_eq(id.remaining_cap(), id.cap - 3000)


func test_record_banked_exactly_cap_does_not_flag() -> void:
	var id := _id(SOLID)
	assert_false(id.record_banked(id.cap), "banking exactly the cap is allowed")
	assert_false(id.flagged)
	assert_true(id.passes_check())
	assert_eq(id.remaining_cap(), 0)


func test_record_banked_crossing_cap_flags_once() -> void:
	var id := _id(CHEAP)
	assert_false(id.record_banked(id.cap - 100))
	assert_true(id.would_flag(101))
	assert_false(id.would_flag(100))
	assert_true(id.record_banked(101), "the crossing call returns true")
	assert_true(id.flagged)
	assert_false(id.passes_check(), "a flagged ID fails its next check")
	assert_false(id.passes_check(), "and keeps failing")
	assert_false(id.record_banked(50), "only the crossing call returns true")
	assert_false(id.record_banked(id.cap * 3), "even a huge later deposit")
	assert_eq(id.banked_under, id.cap - 100 + 101 + 50 + id.cap * 3, "banked_under keeps accumulating")
	assert_false(id.would_flag(10), "already flagged")
	assert_eq(id.remaining_cap(), 0)


func test_record_banked_single_huge_deposit_flags() -> void:
	for grade: int in [CHEAP, SOLID, FLAWLESS]:
		var id := _id(grade)
		assert_true(id.record_banked(id.cap + 1), "grade %d" % grade)
		assert_true(id.flagged)
		assert_eq(id.banked_under, id.cap + 1)


func test_record_banked_ignores_non_positive() -> void:
	var id := _id()
	id.record_banked(500)
	assert_false(id.record_banked(0))
	assert_false(id.record_banked(-200))
	assert_eq(id.banked_under, 500)
	assert_false(id.would_flag(0))


func test_caps_match_tuning_per_grade_when_flagging() -> void:
	var cheap := _id(CHEAP)
	var flawless := _id(FLAWLESS)
	var amount := _grade_cap(CHEAP) + 1
	assert_true(cheap.record_banked(amount))
	assert_false(flawless.record_banked(amount), "same amount is fine on a flawless card")
	assert_true(flawless.passes_check())


func test_burn_fails_every_check() -> void:
	var id := _id(FLAWLESS)
	id.burn()
	assert_true(id.burned)
	for i in 5:
		assert_false(id.passes_check(), "check %d" % i)
	assert_false(id.record_banked(10), "banking doesn't flag a card that is under the cap")
	assert_false(id.passes_check())


func test_burned_and_flagged_both_fail() -> void:
	var id := _id(CHEAP)
	id.record_banked(id.cap + 5)
	id.burn()
	assert_false(id.passes_check())


func test_to_dict_has_all_fields_as_plain_data() -> void:
	var id := _id(SOLID)
	id.record_banked(1234)
	var d := id.to_dict()
	for key: String in ["name", "birthday", "home_state", "grade", "cap", "banked_under", "flagged", "burned"]:
		assert_has(d, key)
	assert_eq(d["name"], "Chet Bonanza")
	assert_eq(d["birthday"], "Mar 14, 1971")
	assert_eq(d["home_state"], "Nevada")
	assert_eq(d["grade"], SOLID)
	assert_eq(d["cap"], _grade_cap(SOLID))
	assert_eq(d["banked_under"], 1234)
	assert_eq(d["flagged"], false)
	assert_eq(d["burned"], false)


func test_from_dict_round_trip() -> void:
	var id := _id(CHEAP)
	id.record_banked(id.cap + 10)
	id.burn()
	var back := FakeId.from_dict(id.to_dict())
	assert_eq(back.to_dict(), id.to_dict())
	assert_false(back.passes_check())


func test_from_dict_survives_json() -> void:
	var id := _id(FLAWLESS)
	id.record_banked(4321)
	var parsed: Variant = JSON.parse_string(JSON.stringify(id.to_dict()))
	assert_true(parsed is Dictionary)
	var back := FakeId.from_dict(parsed)
	assert_eq(back.grade, FLAWLESS)
	assert_eq(back.cap, _grade_cap(FLAWLESS))
	assert_eq(back.banked_under, 4321)
	assert_eq(back.name, id.name)
	assert_true(back.passes_check())


func test_from_dict_missing_cap_uses_grade() -> void:
	var back := FakeId.from_dict({"name": "X Y", "grade": SOLID})
	assert_eq(back.cap, _grade_cap(SOLID))
	assert_eq(back.banked_under, 0)
	assert_false(back.flagged)


func test_copy_is_independent() -> void:
	var id := _id()
	var c := id.copy()
	c.record_banked(c.cap + 1)
	c.burn()
	assert_true(id.passes_check())
	assert_eq(id.banked_under, 0)
	assert_eq(c.name, id.name)


# --- IdGenerator: content ---------------------------------------------------

func test_name_lists_are_big_unique_single_words() -> void:
	assert_gte(IdGenerator.FIRST_NAMES.size(), 30)
	assert_gte(IdGenerator.LAST_NAMES.size(), 30)
	for list: Array[String] in [IdGenerator.FIRST_NAMES, IdGenerator.LAST_NAMES]:
		var seen := {}
		for n: String in list:
			assert_false(seen.has(n), "duplicate name %s" % n)
			seen[n] = true
			assert_false(n.contains(" "), "%s must be one word" % n)
			assert_ne(n, "")


func test_fifty_unique_states() -> void:
	assert_eq(IdGenerator.STATES.size(), 50)
	var seen := {}
	for s: String in IdGenerator.STATES:
		assert_false(seen.has(s), "duplicate state %s" % s)
		seen[s] = true
	for s: String in ["Nevada", "New Jersey", "Hawaii", "Alaska", "West Virginia", "Wyoming"]:
		assert_has(IdGenerator.STATES, s)


func test_generate_fills_every_field() -> void:
	for grade: int in [CHEAP, SOLID, FLAWLESS]:
		var id := IdGenerator.generate(grade, _rng(grade + 7))
		assert_eq(id.grade, grade)
		assert_eq(id.cap, _grade_cap(grade))
		assert_eq(id.banked_under, 0)
		assert_true(id.passes_check())
		_assert_name_from_lists(id.name)
		_assert_birthday_format(id.birthday)
		assert_has(IdGenerator.STATES, id.home_state)


func test_generate_many_seeds_valid_and_varied() -> void:
	var names := {}
	var states := {}
	var months := {}
	var days := {}
	var min_year := 99999
	var max_year := -1
	for s in 2000:
		var id := IdGenerator.generate(CHEAP, _rng(s))
		_assert_name_from_lists(id.name, "seed %d" % s)
		_assert_birthday_format(id.birthday, "seed %d" % s)
		assert_has(IdGenerator.STATES, id.home_state, "seed %d" % s)
		var b := IdGenerator.parse_birthday(id.birthday)
		if b.is_empty():
			continue
		var y: int = b["year"]
		assert_between(y, Tuning.ID_BIRTH_YEAR_MIN, Tuning.ID_BIRTH_YEAR_MAX)
		if b["month"] == 2 and b["day"] == 29:
			assert_true(IdGenerator.is_leap_year(y), "Feb 29 only in leap years: %s" % id.birthday)
		min_year = mini(min_year, y)
		max_year = maxi(max_year, y)
		names[id.name] = true
		states[id.home_state] = true
		months[b["month"]] = true
		days[b["day"]] = true
	assert_gt(names.size(), 1000, "lots of different names")
	assert_eq(states.size(), 50, "every state shows up")
	assert_eq(months.size(), 12, "every month shows up")
	assert_eq(days.size(), 31, "every day of the month shows up")
	assert_lte(min_year, Tuning.ID_BIRTH_YEAR_MIN + 2)
	assert_gte(max_year, Tuning.ID_BIRTH_YEAR_MAX - 2)


func test_generate_is_deterministic_per_seed() -> void:
	for s in [1, 42, 9001]:
		var a := IdGenerator.generate(SOLID, _rng(s))
		var b := IdGenerator.generate(SOLID, _rng(s))
		assert_eq(a.to_dict(), b.to_dict(), "seed %d" % s)
	var rng_a := _rng(5)
	var rng_b := _rng(5)
	for i in 10:
		assert_eq(IdGenerator.generate(CHEAP, rng_a).to_dict(), IdGenerator.generate(CHEAP, rng_b).to_dict())


func test_generate_different_seeds_differ() -> void:
	var a := IdGenerator.generate(CHEAP, _rng(1))
	var differs := false
	for s in range(2, 12):
		if IdGenerator.generate(CHEAP, _rng(s)).describe() != a.describe():
			differs = true
	assert_true(differs)


func test_generate_avoids_names() -> void:
	var first := IdGenerator.generate(CHEAP, _rng(77))
	var again := IdGenerator.generate(CHEAP, _rng(77), [first.name])
	assert_ne(again.name, first.name)
	_assert_name_from_lists(again.name)
	var rng := _rng(3)
	var used: Array = []
	for i in 40:
		var id := IdGenerator.generate(CHEAP, rng, used)
		assert_false(used.has(id.name), "name %s reused" % id.name)
		used.append(id.name)


func test_generate_unknown_grade_is_cheap() -> void:
	var id := IdGenerator.generate(-3, _rng(1))
	assert_eq(id.grade, CHEAP)
	assert_eq(id.cap, _grade_cap(CHEAP))


func test_prices_caps_and_spotting_from_tuning() -> void:
	for grade: int in [CHEAP, SOLID, FLAWLESS]:
		var def: Dictionary = Tuning.ID_GRADES[grade]
		assert_eq(IdGenerator.price(grade), int(def["price"]))
		assert_eq(IdGenerator.cap(grade), int(def["cap"]))
		assert_almost_eq(IdGenerator.spotted_chance(grade), float(def["spotted_chance"]))
		assert_eq(IdGenerator.grade_name(grade), str(def["name"]))
		assert_true(IdGenerator.is_valid_grade(grade))
	assert_lt(IdGenerator.price(CHEAP), IdGenerator.price(SOLID))
	assert_lt(IdGenerator.price(SOLID), IdGenerator.price(FLAWLESS))
	assert_lt(IdGenerator.cap(CHEAP), IdGenerator.cap(SOLID))
	assert_lt(IdGenerator.cap(SOLID), IdGenerator.cap(FLAWLESS))
	assert_gt(IdGenerator.spotted_chance(CHEAP), 0.0)
	assert_eq(IdGenerator.spotted_chance(SOLID), 0.0)
	assert_eq(IdGenerator.spotted_chance(FLAWLESS), 0.0)
	assert_false(IdGenerator.is_valid_grade(17))
	assert_eq(IdGenerator.price(17), IdGenerator.price(CHEAP), "unknown grade prices as cheap")
	assert_eq(IdGenerator.all_grades(), [CHEAP, SOLID, FLAWLESS] as Array[int])


func test_birthday_format_and_parse() -> void:
	assert_eq(IdGenerator.format_birthday(1971, 3, 14), "Mar 14, 1971")
	assert_eq(IdGenerator.format_birthday(2000, 12, 1), "Dec 1, 2000")
	assert_eq(IdGenerator.parse_birthday("Mar 14, 1971"), {"year": 1971, "month": 3, "day": 14})
	assert_eq(IdGenerator.parse_birthday("Feb 29, 1996"), {"year": 1996, "month": 2, "day": 29})
	assert_eq(IdGenerator.parse_birthday("Feb 29, 1997"), {}, "not a leap year")
	assert_eq(IdGenerator.parse_birthday("Apr 31, 1980"), {}, "April has 30 days")
	assert_eq(IdGenerator.parse_birthday("Smarch 3, 1980"), {})
	assert_eq(IdGenerator.parse_birthday("someday"), {})
	assert_eq(IdGenerator.parse_birthday(""), {})
	assert_eq(IdGenerator.parse_birthday("Jan 0, 1980"), {})


func test_calendar_helpers() -> void:
	assert_true(IdGenerator.is_leap_year(1996))
	assert_true(IdGenerator.is_leap_year(2000))
	assert_false(IdGenerator.is_leap_year(1900))
	assert_false(IdGenerator.is_leap_year(1999))
	assert_eq(IdGenerator.days_in_month(2, 1996), 29)
	assert_eq(IdGenerator.days_in_month(2, 1997), 28)
	assert_eq(IdGenerator.days_in_month(4, 1997), 30)
	assert_eq(IdGenerator.days_in_month(12, 1997), 31)
	assert_true(IdGenerator.is_valid_date(1971, 3, 14))
	assert_false(IdGenerator.is_valid_date(1971, 13, 1))
	assert_false(IdGenerator.is_valid_date(1971, 6, 31))


func test_split_name() -> void:
	assert_eq(IdGenerator.split_name("Chet Bonanza"), PackedStringArray(["Chet", "Bonanza"]))
	assert_eq(IdGenerator.split_name("Buck O'Bankroll"), PackedStringArray(["Buck", "O'Bankroll"]))
	assert_eq(IdGenerator.split_name("Cher").size(), 0)
	assert_eq(IdGenerator.split_name("").size(), 0)


# --- IdQuiz: question shape ---------------------------------------------------

func _assert_question(q: Dictionary, id: FakeId, msg: String = "") -> void:
	for key: String in ["field", "prompt", "options", "correct_index"]:
		assert_has(q, key, msg)
	var field: StringName = q["field"]
	assert_has(IdQuiz.FIELDS, field, msg)
	assert_true(typeof(q["field"]) == TYPE_STRING_NAME, "field is a StringName. %s" % msg)
	assert_true(q["prompt"] is String and str(q["prompt"]) != "", "prompt. %s" % msg)
	var options: Array = q["options"]
	assert_eq(options.get_typed_builtin(), TYPE_STRING, "options is Array[String]. %s" % msg)
	assert_eq(options.size(), 3, msg)
	assert_eq(options.size(), Tuning.ID_QUIZ_OPTIONS, msg)
	var correct: int = q["correct_index"]
	assert_between(correct, 0, options.size() - 1, msg)
	var answer := IdQuiz.answer_for(id, field)
	assert_eq(options[correct], answer, "correct option is the card's value. %s" % msg)
	var hits := 0
	var seen := {}
	for o: String in options:
		assert_false(seen.has(o), "options distinct: %s. %s" % [str(options), msg])
		seen[o] = true
		if o == answer:
			hits += 1
	assert_eq(hits, 1, "exactly one correct option: %s. %s" % [str(options), msg])
	assert_true(IdQuiz.is_correct(q, correct))
	for i in options.size():
		if i != correct:
			assert_false(IdQuiz.is_correct(q, i))


func test_question_shape_for_every_field() -> void:
	var id := _id()
	for field: StringName in IdQuiz.FIELDS:
		for s in 20:
			var q := IdQuiz.make_question(id, _rng(s), field)
			assert_eq(q["field"], field)
			_assert_question(q, id, "field %s seed %d" % [field, s])


func test_answer_for_and_labels() -> void:
	var id := _id()
	assert_eq(IdQuiz.answer_for(id, IdQuiz.FIELD_NAME), "Chet Bonanza")
	assert_eq(IdQuiz.answer_for(id, IdQuiz.FIELD_BIRTHDAY), "Mar 14, 1971")
	assert_eq(IdQuiz.answer_for(id, IdQuiz.FIELD_HOME_STATE), "Nevada")
	assert_eq(IdQuiz.answer_for(id, &"shoe_size"), "")
	assert_eq(IdQuiz.answer_for(null, IdQuiz.FIELD_NAME), "")
	assert_eq(IdQuiz.field_label(IdQuiz.FIELD_HOME_STATE), "Home state")
	assert_eq(IdQuiz.FIELDS.size(), 3)


func test_is_correct_rejects_timeouts_and_bad_indexes() -> void:
	var q := IdQuiz.make_question(_id(), _rng(1))
	assert_false(IdQuiz.is_correct(q, -1))
	assert_false(IdQuiz.is_correct(q, 3))
	assert_false(IdQuiz.is_correct({}, 0))


func test_question_is_deterministic_per_seed() -> void:
	var id := IdGenerator.generate(CHEAP, _rng(10))
	for s in [3, 33, 333]:
		var a := IdQuiz.make_question(id, _rng(s))
		var b := IdQuiz.make_question(id, _rng(s))
		assert_eq(a, b, "seed %d" % s)


func test_questions_on_generated_ids_many_seeds() -> void:
	for s in 600:
		var rng := _rng(s)
		var id := IdGenerator.generate(s % 3, rng)
		var q := IdQuiz.make_question(id, rng)
		_assert_question(q, id, "seed %d" % s)


func test_decoys_are_plausible() -> void:
	for s in 400:
		var rng := _rng(1000 + s)
		var id := IdGenerator.generate(CHEAP, rng)
		var real := IdGenerator.parse_birthday(id.birthday)
		for field: StringName in IdQuiz.FIELDS:
			var q := IdQuiz.make_question(id, rng, field)
			for o: String in q["options"]:
				match field:
					IdQuiz.FIELD_NAME:
						_assert_name_from_lists(o, "seed %d" % s)
					IdQuiz.FIELD_HOME_STATE:
						assert_has(IdGenerator.STATES, o, "seed %d" % s)
					IdQuiz.FIELD_BIRTHDAY:
						_assert_birthday_format(o, "seed %d" % s)
						var b := IdGenerator.parse_birthday(o)
						if not b.is_empty():
							assert_lte(absi(int(b["year"]) - int(real["year"])), Tuning.ID_QUIZ_DECOY_YEAR_SPREAD,
								"decoy %s vs %s" % [o, id.birthday])
							assert_between(int(b["year"]), Tuning.ID_BIRTH_YEAR_MIN, Tuning.ID_BIRTH_YEAR_MAX)


func test_tricky_birthdays_get_valid_decoys() -> void:
	for bday: String in ["Feb 29, 1996", "Jan 31, 1975", "Dec 31, 2000", "Feb 28, 1941", "Feb 29, 2000"]:
		var id := FakeId.new("Chet Bonanza", bday, "Ohio")
		for s in 150:
			var q := IdQuiz.make_question(id, _rng(s), IdQuiz.FIELD_BIRTHDAY)
			_assert_question(q, id, "%s seed %d" % [bday, s])
			for o: String in q["options"]:
				_assert_birthday_format(o, "%s seed %d" % [bday, s])


func test_hand_made_ids_still_get_three_distinct_options() -> void:
	var id := FakeId.new("Cher", "someday", "Atlantis")
	for field: StringName in IdQuiz.FIELDS:
		for s in 30:
			var q := IdQuiz.make_question(id, _rng(s), field)
			_assert_question(q, id, "field %s seed %d" % [field, s])
	var empty := FakeId.new()
	for field: StringName in IdQuiz.FIELDS:
		_assert_question(IdQuiz.make_question(empty, _rng(4), field), empty, "empty card %s" % field)


func test_unknown_field_picks_a_real_one() -> void:
	var q := IdQuiz.make_question(_id(), _rng(8), &"shoe_size")
	assert_has(IdQuiz.FIELDS, q["field"])


# --- IdQuiz: fairness over many seeds -----------------------------------------

func test_correct_index_is_uniform() -> void:
	var n := 3000
	var counts := [0, 0, 0]
	var id := _id()
	for s in n:
		var q := IdQuiz.make_question(id, _rng(s))
		counts[int(q["correct_index"])] += 1
	for i in 3:
		assert_between(float(counts[i]) / n, 0.29, 0.38, "index %d share: %s" % [i, str(counts)])


func test_correct_index_is_uniform_per_field() -> void:
	var n := 1500
	for field: StringName in IdQuiz.FIELDS:
		var counts := [0, 0, 0]
		for s in n:
			var rng := _rng(s * 7 + 1)
			var id := IdGenerator.generate(SOLID, rng)
			var q := IdQuiz.make_question(id, rng, field)
			counts[int(q["correct_index"])] += 1
		for i in 3:
			assert_between(float(counts[i]) / n, 0.28, 0.39, "%s index %d: %s" % [field, i, str(counts)])


func test_fields_are_asked_evenly() -> void:
	var n := 3000
	var counts := {}
	for s in n:
		var q := IdQuiz.make_question(_id(), _rng(s + 50000))
		var f: StringName = q["field"]
		counts[f] = int(counts.get(f, 0)) + 1
	assert_eq(counts.size(), 3)
	for f: StringName in IdQuiz.FIELDS:
		assert_between(float(counts.get(f, 0)) / n, 0.29, 0.38, "field %s: %s" % [f, str(counts)])


func test_every_prompt_variant_used() -> void:
	var seen := {}
	for s in 600:
		var q := IdQuiz.make_question(_id(), _rng(s))
		seen[q["prompt"]] = true
	var total := 0
	for f: StringName in IdQuiz.FIELDS:
		total += (IdQuiz.PROMPTS[f] as Array).size()
	assert_eq(seen.size(), total)


## Parts two options share: first/last name, or month/day/year.
func _shared_parts(field: StringName, a: String, b: String) -> int:
	if field == IdQuiz.FIELD_NAME:
		var pa := IdGenerator.split_name(a)
		var pb := IdGenerator.split_name(b)
		return int(pa[0] == pb[0]) + int(pa[1] == pb[1])
	var da := IdGenerator.parse_birthday(a)
	var db := IdGenerator.parse_birthday(b)
	return int(da["year"] == db["year"]) + int(da["month"] == db["month"]) + int(da["day"] == db["day"])


## "Pick the option that has the most in common with the others" must not beat
## a blind guess, or players could pass checks without remembering the card.
func test_most_similar_option_is_no_better_than_guessing() -> void:
	var n := 1500
	for field: StringName in [IdQuiz.FIELD_NAME, IdQuiz.FIELD_BIRTHDAY]:
		var wins := 0.0
		var any_shared := 0
		for s in n:
			var rng := _rng(s * 13 + 5)
			var id := IdGenerator.generate(CHEAP, rng)
			var q := IdQuiz.make_question(id, rng, field)
			var options: Array = q["options"]
			var scores: Array[int] = []
			for i in options.size():
				var score := 0
				for j in options.size():
					if i != j:
						score += _shared_parts(field, options[i], options[j])
				scores.append(score)
			var best: int = scores.max()
			var tied := 0
			for sc: int in scores:
				if sc == best:
					tied += 1
			if scores[int(q["correct_index"])] == best:
				wins += 1.0 / tied
			if best > 0:
				any_shared += 1
		assert_between(wins / n, 0.27, 0.40, "%s: similarity strategy hit rate %f" % [field, wins / n])
		assert_gt(float(any_shared) / n, 0.9, "%s decoys should look like the real answer" % field)


func test_decoys_vary_across_seeds() -> void:
	var id := _id()
	var decoys := {}
	for s in 300:
		var q := IdQuiz.make_question(id, _rng(s), IdQuiz.FIELD_HOME_STATE)
		for o: String in q["options"]:
			if o != id.home_state:
				decoys[o] = true
	assert_gt(decoys.size(), 40, "decoy states spread over the list")
	assert_false(decoys.has("Nevada"))


# --- IdQuiz: spotted on sight -----------------------------------------------

func test_spotted_on_sight_only_cheap() -> void:
	for grade: int in [SOLID, FLAWLESS]:
		var rng := _rng(99)
		var state_before := rng.state
		var id := _id(grade)
		for i in 1000:
			assert_false(IdQuiz.spotted_on_sight(id, rng))
		assert_eq(rng.state, state_before, "zero-chance grades don't consume randomness")
	assert_false(IdQuiz.spotted_on_sight(null, _rng(1)))


func test_spotted_on_sight_rate_matches_tuning() -> void:
	var chance := float(Tuning.ID_GRADES[CHEAP]["spotted_chance"])
	var rng := _rng(2024)
	var id := _id(CHEAP)
	var n := 5000
	var spotted := 0
	for i in n:
		if IdQuiz.spotted_on_sight(id, rng):
			spotted += 1
	assert_almost_eq(float(spotted) / n, chance, 0.03, "spotted %d of %d" % [spotted, n])


func test_spotted_on_sight_deterministic() -> void:
	var id := _id(CHEAP)
	var a := _rng(7)
	var b := _rng(7)
	for i in 50:
		assert_eq(IdQuiz.spotted_on_sight(id, a), IdQuiz.spotted_on_sight(id, b))


# --- Forger -----------------------------------------------------------------

func _watch(forger: Forger) -> Array[StringName]:
	var moves: Array[StringName] = []
	forger.moved.connect(func(where: StringName) -> void: moves.append(where))
	return moves


func test_forger_starts_in_parking_garage() -> void:
	var f := Forger.new()
	assert_eq(f.location(), &"parking_garage")
	assert_eq(f.next_location(), &"restroom")
	assert_almost_eq(f.seconds_until_move(), Tuning.FORGER_MOVE_SECONDS)
	assert_true(f.is_at(&"parking_garage"))
	assert_eq(Forger.LOCATIONS, [&"parking_garage", &"restroom", &"loading_dock"] as Array[StringName])


func test_forger_rotates_and_emits() -> void:
	var f := Forger.new()
	var moves := _watch(f)
	f.tick(Tuning.FORGER_MOVE_SECONDS - 1.0)
	assert_eq(f.location(), &"parking_garage")
	assert_eq(moves.size(), 0)
	assert_almost_eq(f.seconds_until_move(), 1.0)
	f.tick(1.0)
	assert_eq(f.location(), &"restroom")
	assert_eq(moves, [&"restroom"] as Array[StringName])
	f.tick(Tuning.FORGER_MOVE_SECONDS)
	assert_eq(f.location(), &"loading_dock")
	f.tick(Tuning.FORGER_MOVE_SECONDS)
	assert_eq(f.location(), &"parking_garage", "wraps back to the garage")
	assert_eq(moves, [&"restroom", &"loading_dock", &"parking_garage"] as Array[StringName])


func test_forger_frame_ticks_move_on_time() -> void:
	var f := Forger.new()
	var moves := _watch(f)
	var frames := int(round(Tuning.FORGER_MOVE_SECONDS * 60.0))
	for i in frames - 1:
		f.tick(1.0 / 60.0)
	assert_eq(moves.size(), 0, "not before the full stay")
	f.tick(1.0 / 60.0)
	assert_eq(moves.size(), 1, "moves on the last frame of the stay")
	assert_eq(f.location(), &"restroom")
	for i in frames:
		f.tick(1.0 / 60.0)
	assert_eq(moves.size(), 2)
	assert_eq(f.location(), &"loading_dock")


func test_forger_long_tick_moves_several_times() -> void:
	var f := Forger.new()
	var moves := _watch(f)
	f.tick(Tuning.FORGER_MOVE_SECONDS * 4.5)
	assert_eq(moves, [&"restroom", &"loading_dock", &"parking_garage", &"restroom"] as Array[StringName])
	assert_eq(f.location(), &"restroom")
	assert_almost_eq(f.seconds_until_move(), Tuning.FORGER_MOVE_SECONDS * 0.5)


func test_forger_ignores_non_positive_ticks() -> void:
	var f := Forger.new()
	var moves := _watch(f)
	f.tick(0.0)
	f.tick(-500.0)
	assert_eq(moves.size(), 0)
	assert_eq(f.location(), &"parking_garage")
	assert_almost_eq(f.seconds_until_move(), Tuning.FORGER_MOVE_SECONDS)


func test_forger_custom_start() -> void:
	var f := Forger.new(&"loading_dock")
	assert_eq(f.location(), &"loading_dock")
	assert_eq(f.next_location(), &"parking_garage")
	var bad := Forger.new(&"moon")
	assert_eq(bad.location(), &"parking_garage")


func test_forger_to_dict_and_shop() -> void:
	var f := Forger.new()
	f.tick(30.0)
	var d := f.to_dict()
	assert_eq(d["location"], "parking_garage")
	assert_almost_eq(float(d["seconds_until_move"]), Tuning.FORGER_MOVE_SECONDS - 30.0)
	assert_eq(f.price(FLAWLESS), int(Tuning.ID_GRADES[FLAWLESS]["price"]))
	var id := f.make_id(SOLID, _rng(12))
	assert_eq(id.to_dict(), IdGenerator.generate(SOLID, _rng(12)).to_dict())
