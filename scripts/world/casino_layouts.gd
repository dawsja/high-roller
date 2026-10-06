class_name CasinoLayouts
extends RefCounted
## Floor plans for CasinoBuilder: pure data on a 2 m grid, computed from a
## casino's size class. Metres in the XZ plane; a Rect2's position is its
## (min x, min z) corner. The front wall with the entrance is at z = 0 and the
## building runs toward -Z:
##
##   z = -D   staff corridor (lockers, laundry cart) ── back door ─► loading dock
##            back room | security | staff passage | cashier cage | restroom | lounge
##            north aisle (cashier queue)
##            game rows: slots | pit | pit | ... with aisles between blocks
##            south aisle
##   z = 0    gift shop | lobby (entrance doors) | bar | buffet
##   z > 0    sidewalk, exit pad, parking garage
##
## Game blocks are 8 m deep; a tables block holds 4 m table slots in two rows
## facing out to the aisles (dealers back to back in the middle).

const SMALL := &"small"
const MEDIUM := &"medium"
const LARGE := &"large"

const GRID := 2.0
const CORRIDOR_DEPTH := 2.0
const BACK_DEPTH := 6.0
const ROW_DEPTH := 8.0
const TABLE_SLOT := 4.0
const PASSAGE_WIDTH := 2.0
## Front lot (sidewalk, road, exit pad, garage) depth in front of the building.
const LOT_DEPTH := 14.0
const SIDEWALK_DEPTH := 4.0
const GARAGE_WIDTH := 12.0
const DOCK_WIDTH := 12.0
const DOCK_DEPTH := 10.0
## Back-band space left after the fixed rooms becomes a lounge if at least this wide.
const MIN_LOUNGE := 6.0
## Spacing of slot machines along a slots block.
const SLOT_PITCH := 1.5

const _BJ := HR.GameType.BLACKJACK
const _HL := HR.GameType.HIGH_LOW
const _DICE := HR.GameType.DICE
const _ROU := HR.GameType.ROULETTE
const _WHEEL := HR.GameType.BIG_WHEEL

## Per size class. Widths in metres; the blocks of every row plus the aisles
## must add up to the same building width as the back and front bands.
## "games" lists a tables block's games: north row west→east, then south row.
const SPECS := {
	SMALL: {
		"aisle_v": 2.0, "aisle_h": 4.0, "east_aisle": 4.0, "front_depth": 6.0,
		"back_room": 6.0, "security": 8.0, "cashier": 6.0, "restroom": 10.0,
		"gift_shop": 6.0, "lobby": 12.0, "bar": 8.0,
		"rows": [[
			{"id": &"slots", "kind": &"slots", "w": 8.0, "machines": 4},
			{"id": &"pit_a", "kind": &"tables", "w": 8.0, "games": [_BJ, _HL, _BJ, _DICE]},
			{"id": &"pit_b", "kind": &"tables", "w": 8.0, "games": [_ROU, _WHEEL, _DICE, _HL]},
		]],
	},
	MEDIUM: {
		"aisle_v": 4.0, "aisle_h": 4.0, "east_aisle": 4.0, "front_depth": 8.0,
		"back_room": 6.0, "security": 8.0, "cashier": 8.0, "restroom": 10.0,
		"gift_shop": 8.0, "lobby": 12.0, "bar": 12.0,
		"rows": [[
			{"id": &"slots", "kind": &"slots", "w": 8.0, "machines": 5},
			{"id": &"pit_a", "kind": &"tables", "w": 8.0, "games": [_BJ, _BJ, _HL, _HL]},
			{"id": &"pit_b", "kind": &"tables", "w": 8.0, "games": [_ROU, _DICE, _DICE, _ROU]},
			{"id": &"wheel_stage", "kind": &"tables", "w": 4.0, "games": [_WHEEL, _WHEEL]},
		]],
	},
	LARGE: {
		"aisle_v": 4.0, "aisle_h": 4.0, "east_aisle": 4.0, "front_depth": 8.0,
		"back_room": 6.0, "security": 8.0, "cashier": 8.0, "restroom": 10.0,
		"gift_shop": 8.0, "lobby": 12.0, "bar": 14.0,
		"rows": [
			[
				{"id": &"slots", "kind": &"slots", "w": 8.0, "machines": 4},
				{"id": &"pit_a", "kind": &"tables", "w": 8.0, "games": [_BJ, _BJ, _HL, _HL]},
				{"id": &"pit_b", "kind": &"tables", "w": 8.0, "games": [_ROU, _DICE, _DICE, _ROU]},
				{"id": &"high_limit", "kind": &"tables", "w": 8.0, "games": [_BJ, _ROU, _HL, _DICE]},
			],
			[
				{"id": &"slots_b", "kind": &"slots", "w": 8.0, "machines": 4},
				{"id": &"pit_c", "kind": &"tables", "w": 8.0, "games": [_BJ, _HL, _BJ, _DICE]},
				{"id": &"wheel_stage", "kind": &"tables", "w": 8.0, "games": [_WHEEL, _WHEEL, _ROU, _BJ]},
				{"id": &"pit_d", "kind": &"tables", "w": 8.0, "games": [_DICE, _ROU, _HL, _BJ]},
			],
		],
	},
}


## Sal's and the Rusty Spur are small, Neon Oasis and the Riverboat medium,
## the Grand Marquee and the Apex large.
static func size_class(rung: int) -> StringName:
	if rung >= 5:
		return SMALL
	if rung >= 3:
		return MEDIUM
	return LARGE


## The full floor plan for a casino row (see the class doc for the frame).
## Keys: size, w, d, x0, x1, z0 (back wall), front_depth, aisle_v, aisle_h,
## rects (name -> Rect2: corridor, back_room, security, passage, cashier,
## restroom, lounge (may be empty), floor, gift_shop, lobby, bar, buffet,
## lot, sidewalk, garage, dock), door_x (entrance center), walled (Array of
## Rect2 rooms with walls), doors (Array of {a, b: Vector2, kind}),
## bars (Array of {a, b}: the cashier counter), blocks (Array of
## {id, kind, rect, row, games, machines}), h_aisles / v_aisles (aisle
## center lines, z / x).
static func plan(casino: Dictionary) -> Dictionary:
	var size: StringName = size_class(int(casino.get("rung", Tuning.BOTTOM_RUNG)))
	var spec: Dictionary = SPECS[size]
	var av: float = spec["aisle_v"]
	var ah: float = spec["aisle_h"]
	var fd: float = spec["front_depth"]
	var rows: Array = spec["rows"]

	var w: float = float(spec["east_aisle"])
	for b: Dictionary in rows[0]:
		w += float(b["w"])
	w += av * float((rows[0] as Array).size() - 1)
	var d: float = CORRIDOR_DEPTH + BACK_DEPTH + ah * float(rows.size() + 1) + ROW_DEPTH * float(rows.size()) + fd
	var x0: float = -w * 0.5
	var x1: float = w * 0.5
	var z0: float = -d

	var r := {}
	r["corridor"] = Rect2(x0, z0, w, CORRIDOR_DEPTH)
	var bz: float = z0 + CORRIDOR_DEPTH
	var x: float = x0
	for key: String in ["back_room", "security"]:
		r[key] = Rect2(x, bz, spec[key], BACK_DEPTH)
		x += float(spec[key])
	r["passage"] = Rect2(x, bz, PASSAGE_WIDTH, BACK_DEPTH)
	x += PASSAGE_WIDTH
	r["cashier"] = Rect2(x, bz, spec["cashier"], BACK_DEPTH)
	x += float(spec["cashier"])
	var restroom_w: float = spec["restroom"]
	var left: float = x1 - x - restroom_w
	if left < MIN_LOUNGE:
		restroom_w += left
		left = 0.0
	r["restroom"] = Rect2(x, bz, restroom_w, BACK_DEPTH)
	r["lounge"] = Rect2(x + restroom_w, bz, left, BACK_DEPTH)

	var floor_z0: float = bz + BACK_DEPTH
	r["floor"] = Rect2(x0, floor_z0, w, -fd - floor_z0)
	x = x0
	for key: String in ["gift_shop", "lobby", "bar"]:
		r[key] = Rect2(x, -fd, spec[key], fd)
		x += float(spec[key])
	r["buffet"] = Rect2(x, -fd, x1 - x, fd)

	r["lot"] = Rect2(x0, 0.0, w, LOT_DEPTH)
	r["sidewalk"] = Rect2(x0, 0.0, w, SIDEWALK_DEPTH)
	r["garage"] = Rect2(x1 - GARAGE_WIDTH, SIDEWALK_DEPTH, GARAGE_WIDTH, LOT_DEPTH - SIDEWALK_DEPTH)
	r["dock"] = Rect2(x1 - DOCK_WIDTH, z0 - DOCK_DEPTH, DOCK_WIDTH, DOCK_DEPTH)

	var lobby: Rect2 = r["lobby"]
	var door_x: float = lobby.get_center().x
	var sec: Rect2 = r["security"]
	var cash: Rect2 = r["cashier"]
	var rest: Rect2 = r["restroom"]
	var pas: Rect2 = r["passage"]
	var gift: Rect2 = r["gift_shop"]
	var back: Rect2 = r["back_room"]
	var doors: Array = [
		_door(Vector2(door_x - 2.0, 0.0), Vector2(door_x + 2.0, 0.0), &"entrance"),
		_door(Vector2(back.end.x, bz + 2.0), Vector2(back.end.x, bz + 4.0), &"back_room"),
		_door(Vector2(sec.position.x + 4.0, sec.end.y), Vector2(sec.position.x + 6.0, sec.end.y), &"security"),
		_door(Vector2(pas.position.x, pas.end.y), Vector2(pas.end.x, pas.end.y), &"staff"),
		_door(Vector2(pas.position.x, bz), Vector2(pas.end.x, bz), &"staff_inner"),
		_door(Vector2(cash.position.x + 2.0, bz), Vector2(cash.position.x + 4.0, bz), &"cage"),
		_door(Vector2(rest.position.x + 2.0, rest.end.y), Vector2(rest.position.x + 4.0, rest.end.y), &"restroom"),
		_door(Vector2(x1 - 4.0, z0), Vector2(x1 - 2.0, z0), &"dock"),
		_door(Vector2(gift.end.x - 2.0, gift.position.y), Vector2(gift.end.x, gift.position.y), &"gift_shop"),
	]
	var bars: Array = [_door(Vector2(cash.position.x, cash.end.y), Vector2(cash.end.x - 2.0, cash.end.y), &"bars")]
	var walled: Array = [Rect2(x0, z0, w, d), r["corridor"], back, sec, pas, cash, rest, gift]

	var blocks: Array = []
	var h_aisles: Array[float] = [floor_z0 + ah * 0.5]
	var v_aisles: Array[float] = []
	var row_z: float = floor_z0 + ah
	for ri in rows.size():
		var bx: float = x0
		var row: Array = rows[ri]
		for bi in row.size():
			var spec_b: Dictionary = row[bi]
			var block := {
				"id": spec_b["id"],
				"kind": spec_b["kind"],
				"rect": Rect2(bx, row_z, spec_b["w"], ROW_DEPTH),
				"row": ri,
				"games": spec_b.get("games", []),
				"machines": int(spec_b.get("machines", 0)),
			}
			blocks.append(block)
			bx += float(spec_b["w"])
			var gap: float = av if bi < row.size() - 1 else float(spec["east_aisle"])
			if ri == 0:
				v_aisles.append(bx + gap * 0.5)
			bx += gap
		row_z += ROW_DEPTH
		h_aisles.append(row_z + ah * 0.5)
		row_z += ah

	return {
		"size": size, "w": w, "d": d, "x0": x0, "x1": x1, "z0": z0,
		"front_depth": fd, "aisle_v": av, "aisle_h": ah,
		"rects": r, "door_x": door_x, "walled": walled, "doors": doors, "bars": bars,
		"blocks": blocks, "h_aisles": h_aisles, "v_aisles": v_aisles,
	}


## World-space table slots of a tables block: Array of {game_type, transform}.
## The anchor sits at the table center; the seat side is the anchor's local +Z,
## which faces the aisle (north row faces -Z, south row faces +Z).
static func table_slots(block: Dictionary) -> Array:
	var out: Array = []
	var rect: Rect2 = block["rect"]
	var games: Array = block["games"]
	var cols: int = maxi(1, int(rect.size.x / TABLE_SLOT))
	for i in games.size():
		var col: int = i % cols
		var north: bool = i < cols
		var pos := Vector3(rect.position.x + TABLE_SLOT * (float(col) + 0.5), 0.0,
			rect.position.y + (TABLE_SLOT * 0.5 if north else ROW_DEPTH - TABLE_SLOT * 0.5))
		var basis := Basis(Vector3.UP, PI) if north else Basis.IDENTITY
		out.append({"game_type": int(games[i]), "transform": Transform3D(basis, pos)})
	return out


## Slot machine positions of a slots block. Players use the row along the
## block's west edge (cabinets face east, seat side local +Z = world +X);
## patrons sit at the decor row on the east edge (facing west).
## Returns {player: Array[Transform3D], decor: Array[Transform3D]} of cabinet
## transforms (local +Z toward the seat).
static func slot_machines(block: Dictionary) -> Dictionary:
	var rect: Rect2 = block["rect"]
	var count: int = int((rect.size.y - 1.2) / SLOT_PITCH) + 1
	var mine: int = clampi(int(block["machines"]), 1, count)
	var player: Array[Transform3D] = []
	var decor: Array[Transform3D] = []
	var cz: float = rect.get_center().y
	for i in mine:
		var z: float = cz + (float(i) - float(mine - 1) * 0.5) * SLOT_PITCH
		player.append(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(rect.position.x + 1.0, 0.0, z)))
	for i in count:
		var z: float = cz + (float(i) - float(count - 1) * 0.5) * SLOT_PITCH
		decor.append(Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(rect.end.x - 0.8, 0.0, z)))
	return {"player": player, "decor": decor}


static func _door(a: Vector2, b: Vector2, kind: StringName) -> Dictionary:
	return {"a": a, "b": b, "kind": kind}
