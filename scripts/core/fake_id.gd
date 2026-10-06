class_name FakeId
extends RefCounted
## One fake ID card: the name a player plays under. Guards and the cashier ask
## for it (IdQuiz picks one of name / birthday / home_state to quiz on).
##
## Every chip cashed out is banked under the card's name. Banking more than the
## grade's cap flags the name, and a flagged ID fails its next check (and every
## one after: the name is hot for good). A burned ID (its holder reached the back
## room) fails every check. Buy replacements from the Forger.

## Silly generated name, "Chet Bonanza".
var name: String = ""
## "Mar 14, 1971" (see IdGenerator.format_birthday).
var birthday: String = ""
## One of the 50 US states, spelled out: "New Mexico".
var home_state: String = ""
## HR.IdGrade.
var grade: int = HR.IdGrade.CHEAP
## Chips that can be banked under this name before it is flagged (from the grade).
var cap: int = 0
## Chips banked under this name so far.
var banked_under: int = 0
var flagged: bool = false
var burned: bool = false


## Cap comes from Tuning.ID_GRADES for the grade (an unknown grade counts as cheap).
func _init(id_name: String = "", id_birthday: String = "", id_home_state: String = "", id_grade: int = HR.IdGrade.CHEAP) -> void:
	name = id_name
	birthday = id_birthday
	home_state = id_home_state
	grade = id_grade if Tuning.ID_GRADES.has(id_grade) else HR.IdGrade.CHEAP
	cap = int(_grade_def(grade)["cap"])


## True when the card survives a check: not burned and not flagged.
func passes_check() -> bool:
	return not burned and not flagged


## Records chips banked under this name. Returns true only on the call that takes
## banked_under past the cap and flags the ID; false otherwise (including every
## later call once flagged). Non-positive amounts are ignored.
func record_banked(amount: int) -> bool:
	if amount <= 0:
		return false
	banked_under += amount
	if not flagged and banked_under > cap:
		flagged = true
		return true
	return false


## Chips that can still be banked before this cash-out would flag the name.
func remaining_cap() -> int:
	return maxi(0, cap - banked_under)


## Would banking this amount flag the ID? (Cashier warnings, HUD hints.)
func would_flag(amount: int) -> bool:
	return not flagged and amount > 0 and banked_under + amount > cap


## Burned in the back room: fails every check from now on.
func burn() -> void:
	burned = true


## "Cheap", "Solid" or "Flawless".
func grade_name() -> String:
	return str(_grade_def(grade)["name"])


## Chance a guard spots this card as fake on sight (only cheap cards are > 0).
func spotted_chance() -> float:
	return float(_grade_def(grade)["spotted_chance"])


## One-line card text: "Chet Bonanza · Mar 14, 1971 · Nevada".
func describe() -> String:
	return "%s · %s · %s" % [name, birthday, home_state]


func copy() -> FakeId:
	return FakeId.from_dict(to_dict())


## Plain data, safe for JSON, saves and RPC.
func to_dict() -> Dictionary:
	return {
		"name": name,
		"birthday": birthday,
		"home_state": home_state,
		"grade": grade,
		"cap": cap,
		"banked_under": banked_under,
		"flagged": flagged,
		"burned": burned,
	}


## Reads to_dict() output. Missing keys keep their defaults; a missing cap comes
## from the grade.
static func from_dict(d: Dictionary) -> FakeId:
	var id := FakeId.new(str(d.get("name", "")), str(d.get("birthday", "")),
		str(d.get("home_state", "")), int(d.get("grade", HR.IdGrade.CHEAP)))
	if d.has("cap"):
		id.cap = int(d["cap"])
	id.banked_under = int(d.get("banked_under", 0))
	id.flagged = bool(d.get("flagged", false))
	id.burned = bool(d.get("burned", false))
	return id


static func _grade_def(g: int) -> Dictionary:
	if Tuning.ID_GRADES.has(g):
		return Tuning.ID_GRADES[g]
	return Tuning.ID_GRADES[HR.IdGrade.CHEAP]
