class_name IdGenerator
extends RefCounted
## Makes fake IDs for the forger: silly names, real calendar birthdays and one
## of the 50 US states. Static only; randomness comes from the rng passed in, so
## the same seed always prints the same card.
##
## Grade numbers (price, cap, spotted chance) come from Tuning.ID_GRADES. An
## unknown grade is treated as cheap everywhere.

## Big lists on purpose: swapping IDs often means more names to keep straight.
## One word each (IdQuiz splits a full name on the first space).
const FIRST_NAMES: Array[String] = [
	"Chet", "Dolores", "Buck", "Lorraine", "Vinnie", "Mabel", "Duke", "Gladys",
	"Rex", "Bunny", "Velma", "Earl", "Trixie", "Moe", "Bev", "Lance",
	"Peggy", "Rocco", "Doris", "Biff", "Wanda", "Hank", "Candy", "Skip",
	"Marge", "Dusty", "Agnes", "Thaddeus", "Fern", "Buzz", "Ethel", "Clyde",
	"Roxanne", "Murray", "Penny", "Gus", "Lola", "Ike", "Opal", "Sonny",
	"Myrtle", "Dexter", "Ginger", "Waylon", "Bernadette", "Lyle", "Tammy", "Cornelius",
]

const LAST_NAMES: Array[String] = [
	"Bonanza", "McWager", "Luckman", "Doubledown", "Fortunato", "Chipsworth", "Moneybags", "Snakeyes",
	"Cashwell", "Stackhouse", "Bigbucks", "Highcard", "Splitsby", "Pokerton", "Goldtooth", "Jackpott",
	"Fullhouse", "Diceman", "Luckwood", "Hotstreak", "O'Bankroll", "Silverspoon", "Quarterman", "Wagerly",
	"Spinwell", "McCoin", "Flushington", "Oddsworth", "Sevenstar", "Royale", "Payday", "Highwater",
	"Velvetine", "Rainmaker", "Buckshot", "Lowball", "Tumbleweed", "Ace-Jones", "Pennywhistle", "Dealbreaker",
	"Busterton", "Glitterman",
]

const STATES: Array[String] = [
	"Alabama", "Alaska", "Arizona", "Arkansas", "California", "Colorado", "Connecticut",
	"Delaware", "Florida", "Georgia", "Hawaii", "Idaho", "Illinois", "Indiana", "Iowa",
	"Kansas", "Kentucky", "Louisiana", "Maine", "Maryland", "Massachusetts", "Michigan",
	"Minnesota", "Mississippi", "Missouri", "Montana", "Nebraska", "Nevada", "New Hampshire",
	"New Jersey", "New Mexico", "New York", "North Carolina", "North Dakota", "Ohio",
	"Oklahoma", "Oregon", "Pennsylvania", "Rhode Island", "South Carolina", "South Dakota",
	"Tennessee", "Texas", "Utah", "Vermont", "Virginia", "Washington", "West Virginia",
	"Wisconsin", "Wyoming",
]

const MONTHS: Array[String] = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

## Tries before giving up on avoiding a name already in use.
const _AVOID_TRIES := 64


## A new, clean ID of the grade. Names in avoid_names (e.g. the crew's current
## cards) are skipped when possible.
static func generate(grade: int, rng: RandomNumberGenerator, avoid_names: Array = []) -> FakeId:
	var g := grade if is_valid_grade(grade) else HR.IdGrade.CHEAP
	var full_name := random_name(rng)
	var tries := 0
	while avoid_names.has(full_name) and tries < _AVOID_TRIES:
		full_name = random_name(rng)
		tries += 1
	var bday := random_birthday(rng)
	var state := random_state(rng)
	return FakeId.new(full_name, bday, state, g)


static func is_valid_grade(grade: int) -> bool:
	return Tuning.ID_GRADES.has(grade)


## Grades from cheapest to best.
static func all_grades() -> Array[int]:
	var out: Array[int] = []
	for g: int in Tuning.ID_GRADES:
		out.append(g)
	out.sort()
	return out


## Forger's price for a grade.
static func price(grade: int) -> int:
	return int(_def(grade)["price"])


static func cap(grade: int) -> int:
	return int(_def(grade)["cap"])


static func spotted_chance(grade: int) -> float:
	return float(_def(grade)["spotted_chance"])


static func grade_name(grade: int) -> String:
	return str(_def(grade)["name"])


## "Chet Bonanza".
static func random_name(rng: RandomNumberGenerator) -> String:
	var first: String = FIRST_NAMES[rng.randi_range(0, FIRST_NAMES.size() - 1)]
	var last: String = LAST_NAMES[rng.randi_range(0, LAST_NAMES.size() - 1)]
	return "%s %s" % [first, last]


## A real calendar date between Tuning.ID_BIRTH_YEAR_MIN and _MAX: "Mar 14, 1971".
static func random_birthday(rng: RandomNumberGenerator) -> String:
	var year := rng.randi_range(Tuning.ID_BIRTH_YEAR_MIN, Tuning.ID_BIRTH_YEAR_MAX)
	var month := rng.randi_range(1, 12)
	var day := rng.randi_range(1, days_in_month(month, year))
	return format_birthday(year, month, day)


static func random_state(rng: RandomNumberGenerator) -> String:
	return STATES[rng.randi_range(0, STATES.size() - 1)]


## Month is 1-12: format_birthday(1971, 3, 14) -> "Mar 14, 1971".
static func format_birthday(year: int, month: int, day: int) -> String:
	return "%s %d, %d" % [MONTHS[clampi(month, 1, 12) - 1], day, year]


## Reads format_birthday() output back into {year, month, day}. Returns {} for
## text that isn't in that format or isn't a real date.
static func parse_birthday(text: String) -> Dictionary:
	var parts := text.strip_edges().replace(",", "").split(" ", false)
	if parts.size() != 3:
		return {}
	var month := MONTHS.find(parts[0]) + 1
	if month <= 0 or not parts[1].is_valid_int() or not parts[2].is_valid_int():
		return {}
	var day := parts[1].to_int()
	var year := parts[2].to_int()
	if not is_valid_date(year, month, day):
		return {}
	return {"year": year, "month": month, "day": day}


static func is_valid_date(year: int, month: int, day: int) -> bool:
	return month >= 1 and month <= 12 and day >= 1 and day <= days_in_month(month, year)


static func days_in_month(month: int, year: int) -> int:
	match month:
		2:
			return 29 if is_leap_year(year) else 28
		4, 6, 9, 11:
			return 30
		_:
			return 31


static func is_leap_year(year: int) -> bool:
	return (year % 4 == 0 and year % 100 != 0) or year % 400 == 0


## ["Chet", "Bonanza"]: first word and the rest. Empty for a name without both.
static func split_name(full_name: String) -> PackedStringArray:
	var s := full_name.strip_edges()
	var space := s.find(" ")
	if space <= 0 or space >= s.length() - 1:
		return PackedStringArray()
	return PackedStringArray([s.substr(0, space), s.substr(space + 1).strip_edges()])


static func _def(grade: int) -> Dictionary:
	if Tuning.ID_GRADES.has(grade):
		return Tuning.ID_GRADES[grade]
	return Tuning.ID_GRADES[HR.IdGrade.CHEAP]
