class_name IdQuiz
extends RefCounted
## The ID check: a guard (or the cashier) asks one detail from the card and the
## player picks from Tuning.ID_QUIZ_OPTIONS answers. Static only.
##
## Decoys look exactly like real answers so only memory helps:
## - Names and birthdays use a 2x2 grid. Two parts of the real answer each get
##   one alternative (first/last name; two of month/day/year, the third shared
##   by every option). The options are the real answer plus two of the other
##   three grid cells, picked at random. In the resulting L shape the real
##   answer is the corner, an arm or the other arm with equal odds, so "pick the
##   option that shares the most with the others" is right only 1 time in 3.
## - Home states are other states picked uniformly.
## Decoy names come from IdGenerator's name lists, decoy birthdays are real
## dates near the real one, and correct_index is uniform over the slots.

const FIELD_NAME := &"name"
const FIELD_BIRTHDAY := &"birthday"
const FIELD_HOME_STATE := &"home_state"
const FIELDS: Array[StringName] = [FIELD_NAME, FIELD_BIRTHDAY, FIELD_HOME_STATE]

## What the guard says, by field. One is picked at random.
const PROMPTS := {
	FIELD_NAME: ["Name on the card?", "And you are...?", "What's the name, pal?"],
	FIELD_BIRTHDAY: ["Date of birth?", "When's your birthday?", "Birthday. Quick."],
	FIELD_HOME_STATE: ["Where are you from?", "Home state?", "Which state issued this?"],
}

const FIELD_LABELS := {
	FIELD_NAME: "Name",
	FIELD_BIRTHDAY: "Birthday",
	FIELD_HOME_STATE: "Home state",
}

## Rejection-sampling tries for a birthday grid where every cell is a real date.
const _GRID_TRIES := 32
## Tries for a fresh random decoy that isn't already an option.
const _RANDOM_TRIES := 256


## {field: StringName, prompt: String, options: Array[String], correct_index: int}.
## Asks a random field, or `field` when it is one of FIELDS. Options are distinct
## and exactly one equals the card's value.
static func make_question(id: FakeId, rng: RandomNumberGenerator, field: StringName = &"") -> Dictionary:
	var f := field
	if not FIELDS.has(f):
		f = FIELDS[rng.randi_range(0, FIELDS.size() - 1)]
	var answer := answer_for(id, f)
	var count := option_count()
	var decoys := _decoys(f, answer, count - 1, rng)
	var correct := rng.randi_range(0, count - 1)
	var options: Array[String] = []
	var next := 0
	for i in count:
		if i == correct:
			options.append(answer)
		else:
			options.append(decoys[next])
			next += 1
	var prompts: Array = PROMPTS[f]
	var prompt: String = prompts[rng.randi_range(0, prompts.size() - 1)]
	return {"field": f, "prompt": prompt, "options": options, "correct_index": correct}


## Did the player pick the right option? Out-of-range picks (and timeouts, -1) are wrong.
static func is_correct(question: Dictionary, option_index: int) -> bool:
	return option_index >= 0 and option_index == int(question.get("correct_index", -1))


## The card's value for a field ("" for an unknown field or null card).
static func answer_for(id: FakeId, field: StringName) -> String:
	if id == null:
		return ""
	match field:
		FIELD_NAME:
			return id.name
		FIELD_BIRTHDAY:
			return id.birthday
		FIELD_HOME_STATE:
			return id.home_state
	return ""


## HUD label: "Name", "Birthday", "Home state".
static func field_label(field: StringName) -> String:
	return str(FIELD_LABELS.get(field, ""))


static func option_count() -> int:
	return maxi(2, Tuning.ID_QUIZ_OPTIONS)


## Does security spot the card as fake at a glance? Only grades with a
## spotted_chance above 0 (cheap) ever are; better grades never touch the rng.
static func spotted_on_sight(id: FakeId, rng: RandomNumberGenerator) -> bool:
	if id == null:
		return false
	var chance := id.spotted_chance()
	if chance <= 0.0:
		return false
	return rng.randf() < chance


# --- Decoys -----------------------------------------------------------------

## `count` distinct decoys, none equal to `answer`.
static func _decoys(field: StringName, answer: String, count: int, rng: RandomNumberGenerator) -> Array[String]:
	var out: Array[String] = []
	match field:
		FIELD_NAME:
			out = _grid_pick(_name_grid(answer, rng), answer, count, rng)
		FIELD_BIRTHDAY:
			out = _grid_pick(_birthday_grid(answer, rng), answer, count, rng)
		FIELD_HOME_STATE:
			out = _state_decoys(answer, count, rng)
	_fill_random(out, field, answer, count, rng)
	return out


## The three non-answer cells of a name grid, or [] if the answer isn't "First Last".
static func _name_grid(answer: String, rng: RandomNumberGenerator) -> Array[String]:
	var cells: Array[String] = []
	var parts := IdGenerator.split_name(answer)
	if parts.size() != 2:
		return cells
	var first2 := _pick_other(IdGenerator.FIRST_NAMES, parts[0], rng)
	var last2 := _pick_other(IdGenerator.LAST_NAMES, parts[1], rng)
	cells.append("%s %s" % [parts[0], last2])
	cells.append("%s %s" % [first2, parts[1]])
	cells.append("%s %s" % [first2, last2])
	return cells


## The three non-answer cells of a birthday grid where all four cells are real
## dates, or [] if the answer can't be parsed or no grid was found.
static func _birthday_grid(answer: String, rng: RandomNumberGenerator) -> Array[String]:
	var cells: Array[String] = []
	var real := IdGenerator.parse_birthday(answer)
	if real.is_empty():
		return cells
	var y: int = real["year"]
	var m: int = real["month"]
	var d: int = real["day"]
	var years := _decoy_years(y)
	for _attempt in _GRID_TRIES:
		var y2: int = years[rng.randi_range(0, years.size() - 1)]
		var m2 := _other_int(1, 12, m, rng)
		var d2 := _other_int(1, 31, d, rng)
		# Which part stays the same on every option: 0 year, 1 day, 2 month.
		var fixed := rng.randi_range(0, 2)
		var grid: Array = []
		match fixed:
			0:
				grid = [[y, m, d2], [y, m2, d], [y, m2, d2]]
			1:
				grid = [[y2, m, d], [y, m2, d], [y2, m2, d]]
			_:
				grid = [[y, m, d2], [y2, m, d], [y2, m, d2]]
		var ok := true
		for cell: Array in grid:
			if not IdGenerator.is_valid_date(cell[0], cell[1], cell[2]):
				ok = false
				break
		if ok:
			for cell: Array in grid:
				cells.append(IdGenerator.format_birthday(cell[0], cell[1], cell[2]))
			return cells
	return cells


## Years within Tuning.ID_QUIZ_DECOY_YEAR_SPREAD of `year`, kept inside the
## range IDs are printed with when that leaves any.
static func _decoy_years(year: int) -> Array[int]:
	var spread := maxi(1, Tuning.ID_QUIZ_DECOY_YEAR_SPREAD)
	var out: Array[int] = []
	for y in range(year - spread, year + spread + 1):
		if y != year and y >= Tuning.ID_BIRTH_YEAR_MIN and y <= Tuning.ID_BIRTH_YEAR_MAX:
			out.append(y)
	if out.is_empty():
		for y in range(year - spread, year + spread + 1):
			if y != year:
				out.append(y)
	return out


static func _state_decoys(answer: String, count: int, rng: RandomNumberGenerator) -> Array[String]:
	var pool: Array[String] = []
	for s: String in IdGenerator.STATES:
		if s != answer:
			pool.append(s)
	_shuffle(pool, rng)
	var out: Array[String] = []
	for s: String in pool:
		if out.size() >= count:
			break
		out.append(s)
	return out


## Up to `count` grid cells in random order, skipping any equal to the answer.
static func _grid_pick(cells: Array[String], answer: String, count: int, rng: RandomNumberGenerator) -> Array[String]:
	var out: Array[String] = []
	_shuffle(cells, rng)
	for c: String in cells:
		if out.size() >= count:
			break
		if c != answer and not out.has(c):
			out.append(c)
	return out


## Tops `out` up to `count` with fresh random values of the field's format.
static func _fill_random(out: Array[String], field: StringName, answer: String, count: int, rng: RandomNumberGenerator) -> void:
	var tries := 0
	while out.size() < count and tries < _RANDOM_TRIES:
		tries += 1
		var v := ""
		match field:
			FIELD_NAME:
				v = IdGenerator.random_name(rng)
			FIELD_BIRTHDAY:
				v = IdGenerator.random_birthday(rng)
			_:
				v = IdGenerator.random_state(rng)
		if v != answer and not out.has(v):
			out.append(v)
	# Only reachable with absurd option counts: number the leftovers so options stay distinct.
	var n := 2
	while out.size() < count:
		var v := "%s %d" % [answer, n]
		n += 1
		if not out.has(v):
			out.append(v)


## A uniformly picked list entry other than `exclude`.
static func _pick_other(list: Array[String], exclude: String, rng: RandomNumberGenerator) -> String:
	var pool: Array[String] = []
	for s: String in list:
		if s != exclude:
			pool.append(s)
	return pool[rng.randi_range(0, pool.size() - 1)]


## A uniform int in [low, high] other than `exclude`.
static func _other_int(low: int, high: int, exclude: int, rng: RandomNumberGenerator) -> int:
	if exclude < low or exclude > high:
		return rng.randi_range(low, high)
	var v := rng.randi_range(low, high - 1)
	return v + 1 if v >= exclude else v


## Fisher-Yates with the injected rng.
static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
