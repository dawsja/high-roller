# Architecture

High Roller is split into a pure-logic **simulation** (`scripts/core/`) and a **world** of Godot nodes (`scripts/world/`, `scripts/ui/`) that renders it and sends it requests.

The design doc says the host owns game results, Heat, guards and posters, and each client owns its own movement. The split mirrors that: only the host runs the simulation. In single-player (phase 1) the local machine is the host. In phase 2, client requests become RPCs to the host's `FloorSim` and its events are broadcast back; nothing in `scripts/core/` changes.

```
input ─► world nodes ──requests──► FloorSim (host only) ──events──► world nodes / HUD
                                     │
           HeatMeter · TableState · GameResolver · Outfit · FakeId
           PosterBoard · Wallet · Cashier · RunState · GuardBrain
```

## Rules for `scripts/core/`

- `extends RefCounted` with a `class_name`. No `Node`, no autoloads, no `Input`, no scene tree.
- Randomness only from a `RandomNumberGenerator` passed in. Same seed, same results.
- Numbers from `Tuning`, enums from `HR`. Don't add magic numbers; if a constant is missing, add it to `tuning.gd` near related ones.
- Player ids are `int` (network peer ids; the local player is `1`). Table, area and casino ids are `StringName`.
- Signals carry plain data so they can be forwarded over RPC later.

## Core modules and contracts

Names and signatures below are the contract other modules code against. Extra helpers are fine; renaming or dropping these is not.

### Heat — `heat_meter.gd`, `heat_rules.gd`

`class_name HeatMeter`
- `signal changed(value: float, delta: float, reason: StringName)`
- `signal level_changed(old_level: int, new_level: int)`
- `var value: float` (read-only by convention), `func _init(initial: float = 0.0)`
- `func add(amount: float, reason: StringName) -> float` — signed amount; clamps to `[0, Tuning.HEAT_MAX]`; returns the applied delta; emits only if the value changed.
- `func raise_to(min_value: float, reason: StringName) -> float` — e.g. a tackler "goes straight to Wanted".
- `func level() -> int` and `static func level_for(value: float) -> int` (`HR.HeatLevel`).
- `func reset() -> void`

`class_name HeatRules` (static functions only)
- Reason constants: `WIN`, `STREAK`, `CAMPING`, `LOSE_ON_PURPOSE`, `AREA_CHANGE`, `OFF_TABLE`, `SLOT_BLEND`, `FLOOR_DECAY`, `CHANGE_OUTFIT`, `RUN_IN_VIEW`, `TABLE_JUMP`, `BUMP_GUARD`, `KNOCK_OVER`, `POSTER_MATCH`, `CASH_OUT`, `CAMERA`, `TACKLE`, `SHARED_ROLL` (all `StringName`).
- `static func win_heat(game_type: int, bet: int, max_bet: int, streak: int, number_bet: bool = false) -> float` — base by heat class × bet scale + streak step × (streak − 1). Streak is the count including this win (1 = first win).
- `static func passive_rate(ctx: Dictionary) -> float` — Heat per second from the current situation. Keys (all optional): `seated_game: int` (−1 = not seated), `seconds_at_table: float`, `zone: int` (`HR.ZoneType`), `running_in_view: bool`, `in_camera_view: bool`. Covers camping, slot blend, off-table zones, floor decay, running and cameras.
- `static func gain_multiplier(ctx: Dictionary) -> float` — `ctx.pit_boss_view: bool` → `Tuning.PIT_BOSS_HEAT_MULT`. Applies to positive gains only.
- `static func cash_out_heat(amount: int, max_bet: int) -> float`

### Table games — `table_games.gd`, `table_state.gd`, `bet_result.gd`, `game_resolver.gd`, `high_low_run.gd`, `blackjack_round.gd`

The host rolls the result first; the detail dictionary describes what the table should animate to match it. No round runs longer than 10 s.

`class_name TableGames` (static): `def(game_type: int) -> Dictionary` (copy of `Tuning.GAMES[type]` plus `type`), `all_types() -> Array[int]`, `display_name(game_type: int, rung: int) -> String` (bottom two rungs reskin: e.g. bingo, scratch cards, coin pusher).

`class_name TableState`
- `var id: StringName`, `var game_type: int`, `var area_id: StringName`, `var closed: bool` (fire alarm)
- per player: seated seconds, streak, cooled flag
- `func _init(id: StringName, game_type: int, area_id: StringName)`
- `seat(pid)`, `leave(pid)` (clears streak and cooled for pid), `is_seated(pid) -> bool`, `seated_players() -> Array[int]`, `tick(delta)` (adds seated time)
- `seconds_seated(pid) -> float`, `streak(pid) -> int`, `mark_cooled(pid)` (dealer swap at Watched), `is_cooled(pid) -> bool`, `win_rate_for(pid) -> float`

`class_name BetResult`: `pid`, `table_id`, `game_type`, `bet`, `won: bool`, `payout: int` (chips returned to pocket, 0 on loss), `net: int` (payout − bet), `heat: float` (signed: positive for a win, `Tuning.LOSE_ON_PURPOSE_HEAT` for a thrown loss, 0 for an honest loss), `streak: int`, `intentional_loss: bool`, `loud: bool`, `jackpot: bool`, `detail: Dictionary`, `to_dict() -> Dictionary`.

`class_name GameResolver` (static)
- `resolve(table: TableState, pid: int, bet: int, choice: Dictionary, rng: RandomNumberGenerator, max_bet: int, payout_bonus: float = 1.0) -> BetResult` — single-shot games: SLOTS, BIG_WHEEL, DICE (solo), ROULETTE. Updates the table streak. `choice.throw = true` forces a loss (lose on purpose). Roulette: `choice.kind` = `"color"` (with `choice.color` `"red"`/`"black"`) or `"number"` (with `choice.number` 0–36). Slots: rare jackpot (`Tuning.SLOT_JACKPOT_CHANCE`) is loud. Big wheel is always loud.
- `resolve_shared_roll(table: TableState, bets: Array, rng, max_bet: int, payout_bonus: float = 1.0) -> Dictionary` — dice: everyone bets on one roll; `bets` items are `{pid, bet, throw}`; returns `pid -> BetResult`; the crew's total win Heat is split evenly among winners.
- detail examples: slots `{reels: [3 symbols]}`; wheel `{segment: int, label: String}`; dice `{dice: [d1, d2], total, call}`; roulette `{number, color}`; consistent with `won`.

`class_name HighLowRun` — cash out or double. `func _init(table, pid, bet, rng, max_bet, payout_bonus)`; `var pot: int`, `var current_card: int` (2–14), `var streak: int`, `var finished: bool`; `guess(higher: bool, throw: bool = false) -> BetResult` (pre-rolled at the table win rate; on a win the pot doubles; the card shown matches); `cash_out() -> BetResult` (payout = pot). Heat comes per winning guess with the high-low streak step.

`class_name BlackjackRound` — hit or stand only. `func _init(table, pid, bet, rng, max_bet, payout_bonus)`; the outcome is rolled up front; `var player_cards: Array[int]`, `var dealer_cards: Array[int]` (dealer hole card hidden until stand), `hit() -> int` (dealt card; cards are chosen so a pre-rolled win never busts unless the player keeps hitting past 21 on purpose), `stand() -> BetResult`, `player_total() -> int`, `finished: bool`. Hitting past 21 is a deliberate loss (`intentional_loss = true`).

### Identity — `outfit.gd`, `outfit_catalog.gd`, `wanted_poster.gd`, `poster_board.gd`, `fake_id.gd`, `id_generator.gd`, `id_quiz.gd`, `forger.gd`

`class_name Outfit`: `var pieces: Dictionary` (`HR.OutfitSlot` → piece id `StringName`); `get_piece(slot)`, `set_piece(slot, id)`, `matches(other: Outfit, ignore_slots: Array = []) -> int`, `is_recognized_as(record: Outfit, ignore_slots: Array = []) -> bool` (≥ `Tuning.RECOGNIZE_MATCHES`), `copy() -> Outfit`, `to_dict()`, `static from_dict(d) -> Outfit`, `is_staff_uniform() -> bool`, `describe() -> String`.

`class_name OutfitCatalog` (static): pieces per slot with display name and color; `pieces_for(slot) -> Array[StringName]`, `piece_name(id) -> String`, `piece_color(id) -> Color`, `piece_price(id) -> int`, `random_outfit(rng) -> Outfit` (never staff uniform), `staff_uniform() -> Outfit`.

`class_name WantedPoster`: `id: int`, `casino_id: StringName`, `pid: int`, `outfit: Outfit` (copy at print time), `defaced_slots: Array[int]`, `matches(outfit: Outfit) -> bool` (recognized on the slots not defaced), `deface(slot)`.

`class_name PosterBoard` — lives for the whole run, so posters stay up between visits. `signal poster_printed(poster)`, `signal poster_removed(poster_id)`; `print_poster(casino_id, pid, outfit) -> WantedPoster`, `posters_in(casino_id) -> Array`, `matching_poster(casino_id, outfit) -> WantedPoster` (or null), `tear_down(poster_id) -> bool`, `deface(poster_id, slot) -> bool`.

`class_name FakeId`: `name`, `birthday`, `home_state` (String), `grade: int`, `cap: int`, `banked_under: int`, `flagged: bool`, `burned: bool`; `passes_check() -> bool` (not burned, not flagged), `record_banked(amount) -> bool` (true if this crossed the cap and flagged it), `burn()`, `to_dict()`.

`class_name IdGenerator` (static): silly generated names; `generate(grade: int, rng) -> FakeId`; `price(grade) -> int`.

`class_name IdQuiz` (static): `make_question(id: FakeId, rng) -> Dictionary` → `{field: StringName, prompt: String, options: Array[String] (3), correct_index: int}`; `spotted_on_sight(id: FakeId, rng) -> bool` (cheap IDs, by `spotted_chance`).

`class_name Forger`: moves between `&"parking_garage"`, `&"restroom"`, `&"loading_dock"`; `tick(delta)`, `location() -> StringName`, `signal moved(location)`.

### Economy and ladder — `wallet.gd`, `cashier.gd`, `casino_ladder.gd`, `run_state.gd`

`class_name Wallet` (per player): `pocket: int`, `lifetime_banked: int`; `add(amount)`, `spend(amount) -> bool`, `lose_pocket() -> int`, `give_to(other: Wallet, amount) -> bool`.

`class_name Cashier` (static): `cash_out(wallet: Wallet, id: FakeId, amount: int, max_bet: int) -> Dictionary` → `{ok: bool, reason: StringName, banked: int, heat: float, flagged: bool}`. Fails with `&"bad_id"` if the ID doesn't pass, `&"not_enough"` if pocket is short. A successful cash-out moves chips out of the pocket and records them against the ID cap. The caller adds the banked chips to `RunState`.

`class_name CasinoLadder` (static): `casino(rung) -> Dictionary`, `by_id(id) -> Dictionary`, `buy_in_to_leave(rung) -> int` (buy-in of rung − 1; 0 at the top), `climb_target(rung, banked) -> int` (stretch rule: `banked >= Tuning.STRETCH_MULT × buy_in_to_leave(rung)` and rung − 2 ≥ top → rung − 2; else `banked >= buy_in_to_leave(rung)` → rung − 1; else `rung`), `climb_cost(rung, target) -> int` (buy-in, or the doubled buy-in for a stretch), `drop_target(rung) -> int` (never below the bottom).

`class_name RunState` — crew-level run. Signals: `strike_added(strikes)`, `thrown_out(from_rung, to_rung)`, `climbed(from_rung, to_rung)`, `banked(amount, total)`.
- `rung: int` (starts at `Tuning.TOP_RUNG`), `strikes: int`, `bank: int` (crew chips banked, spendable on buy-ins; carried between visits), `top_banked: int` (chips banked while at the top rung — score, never spent), `top_seconds: float`, `elapsed_seconds: float`, `posters: PosterBoard`, `fire_alarm_used: bool` (per visit), `visits: int`.
- `casino() -> Dictionary`, `add_bank(amount)` (at the top rung it goes to `top_banked`, otherwise to `bank`), `add_strike() -> bool` (true when it hits `Tuning.STRIKES_TO_THROW_OUT`), `throw_out() -> int` (drops a rung, resets strikes and per-visit state; at the bottom it's a curb timeout and the rung stays), `can_climb() -> bool`, `climb() -> int` (spends the buy-in(s) from `bank`), `tick(delta)`, `score() -> int` (`top_banked + floor(top_seconds / 60) × Tuning.SCORE_PER_MINUTE_AT_TOP`).

### Guards — `perception.gd`, `guard_brain.gd`

`class_name Perception` (static): `in_vision_cone(origin: Vector3, forward: Vector3, target: Vector3, fov_degrees: float, range: float) -> bool` (horizontal plane), `can_hear(listener: Vector3, noise_pos: Vector3, radius: float) -> bool`, `pick_target(known_heat: Dictionary) -> int` (highest Heat, −1 if empty; ties by lowest pid).

`class_name GuardBrain` — pure state machine; the guard node feeds it perception and executes its intent.
- `signal state_changed(old_state: int, new_state: int)`
- `var state: int` (`HR.GuardState`), `var target_pid: int`, `var security_type: int`
- `func _init(patrol_points: Array[Vector3], security_type: int = HR.SecurityType.FLOOR_GUARD)`
- `func update(delta: float, ctx: Dictionary) -> Dictionary`
- ctx keys: `position: Vector3`, `seen: Array` of `{pid, position, heat, matches_poster: bool, running: bool, staff_uniform: bool, available: bool}` (available = can be grabbed: not carried/detained/on curb), `noises: Array` of `{position, radius, kind}`, `id_check: int` (0 none/pending, 1 passed, 2 failed), `reached_destination: bool`, `at_back_room: bool`, `stunned: bool` (bumped or tackled this frame), `freed: bool` (a carried player was freed), `fire_alarm: bool`.
- intent keys: `move_to: Vector3` (or `null` to stand), `speed: float`, `face: Vector3` (or `null`), `action: StringName` — one of `&""`, `&"ask_id"` (start the quiz with `target_pid`), `&"grab"`, `&"drop_at_back_room"`, `&"release"`.
- Behavior (see design doc): patrol a looped route; investigate heard noises; at Suspected or on a poster match walk over (`TALK_RANGE`) and ask for ID (undercover skips this and grabs); pass → back to patrol; fail or walk away → chase; Wanted → chase; within `GRAB_RANGE` while chasing → grab → carry to back room; lose sight → search last known spot → patrol. Always targets the highest Heat it knows about (remembered for `GUARD_MEMORY_SECONDS`). Ignores staff uniforms below Wanted. Stunned for `STUN_SECONDS` then searches. Fire alarm: everyone off the floor (patrol paused, move to the first patrol point). Unnoticed and Watched players are never approached.

### Simulation facade — `player_state.gd`, `floor_sim.gd`

`class_name PlayerState`: `pid`, `display_name`, `heat: HeatMeter`, `wallet: Wallet`, `outfit: Outfit`, `stash: Array[Outfit]`, `ids: Array[FakeId]`, `id_index: int`, `status: int` (`HR.PlayerStatus`), `zone: int`, `area_id: StringName`, `table_id: StringName`, `recorded_look: Outfit` (what security recorded at Suspected; null if none), timers.

`class_name FloorSim` — the host-authoritative game. One instance per casino visit; `RunState` persists across visits. Emits everything through one signal so it can be forwarded over the network:
- `signal event(kind: StringName, data: Dictionary)` — kinds include `&"heat"`, `&"level"`, `&"bet"`, `&"poster"`, `&"id_check"`, `&"id_result"`, `&"caught"`, `&"freed"`, `&"detained"`, `&"rejoined"`, `&"strike"`, `&"thrown_out"`, `&"climbed"`, `&"banked"`, `&"noise"`, `&"notify"`, `&"dealer_swap"`, `&"fire_alarm"`, `&"forger_moved"`.
- Setup: `_init(run: RunState, seed: int)`, `add_player(pid, display_name) -> PlayerState`, `register_table(id, game_type, area_id)`.
- Requests (return a result dictionary or object and emit events): `sit`, `stand`, `place_bet`, `start_high_low`, `start_blackjack`, `cash_out`, `enter_zone(pid, zone, area_id)`, `change_outfit(pid, outfit)`, `buy_id(pid, grade)`, `swap_id(pid, index)`, `give_chips(from, to, amount)`, `distraction(pid, kind, position)`, `report_seen(pid, ctx)`, `start_id_check(pid)`, `answer_id_check(pid, option_index)`, `caught(pid)`, `freed(pid, tackler_pid)`, `reach_back_room(pid)`, `try_climb()`, `tick(delta)`.
- Queries: `player(pid)`, `table(id)`, `casino()`, `score()`, `snapshot() -> Dictionary` (full state for late joiners and the HUD).

## World layer (phase 1)

Godot nodes that render the simulation and turn input into requests. Single player for now (pid 1), built so phase 2 can turn requests into RPCs to the host.

```
main.gd ─► TitleScreen ─► CasinoDirector (one per visit) ◄─ SimHost (RunState + FloorSim; the RPC boundary later)
                              ├─ CasinoMap from CasinoBuilder: geometry, nav, zones, interactables, anchors, poster boards
                              ├─ TableNode × n, PlayerCharacter(s), GuardNPC × n, SecurityCamera × n, PatronCrowd, forger NPC
                              └─ UI: Hud, BetPanel, IdQuizPanel, CashierPanel, WardrobePanel, ForgerPanel, menus, DebugOverlay
```

Rules
- World nodes never change chips, Heat, IDs or outfits themselves. Gameplay nodes (player, guards, cameras, tables, map) only emit signals and expose methods; `CasinoDirector` wires them to `SimHost` requests and feeds `SimHost.sim_event` back to them and the UI.
- Dependencies are injected with `setup(...)`; no autoloads, no tree-wide searches.
- Physics layers: 1 world, 2 player, 3 guard, 4 patron, 5 interactable. Guards and players collide with world, each other and patrons (so a crowd blocks a guard).
- Input actions are registered in code by `InputSetup.ensure_actions()` (no InputMap in project.godot).
- Art is graybox low poly built from primitives (`BoxMesh`, `CylinderMesh`, `CapsuleMesh`, `PrismMesh`, `SphereMesh`) with flat `StandardMaterial3D` colors from the casino palette (`Tuning.CASINOS`) and `OutfitCatalog`, on a 2 m grid. Blender assets replace these later.

### Contracts between world modules

`InputSetup` (static, `scripts/world/input_setup.gd`): actions `move_forward/back/left/right` (WASD + arrows), `run` (Shift), `jump` (Space; also struggle while carried), `dive` (Ctrl), `interact` (E, hold for hold-interactions), `tackle` (F), `throw_chips` (G), `knock_over` (Q), `pause` (Esc), `toggle_debug` (F3), `ui_quiz_1/2/3` (1, 2, 3).

`Interactable` (`scripts/world/interactable.gd`, `extends Area3D`, layer 5): `kind: StringName` (`&"table"`, `&"cashier"`, `&"restroom"`, `&"gift_shop"`, `&"forger"`, `&"poster"`, `&"tray"`, `&"fire_alarm"`, `&"laundry_cart"`, `&"staff_locker"`, `&"exit"`, `&"slot_alarm"`), `prompt: String`, `data: Dictionary` (e.g. `{table_id}`, `{poster_id}`), `hold_seconds: float` (0 = press), `enabled: bool`; `signal used(user: Node3D, interactable: Interactable)`; `func use(user: Node3D) -> void`.

`CasinoZone` (`scripts/world/casino_zone.gd`, `extends Area3D`, monitors layer 2): `zone_type: int` (`HR.ZoneType`), `area_id: StringName`; `signal player_entered(player: Node3D, zone: CasinoZone)`.

`CasinoBuilder` (static) `build(casino: Dictionary, seed: int) -> CasinoMap`. `CasinoMap extends Node3D` (add it to the tree, then call `bake_navigation()`):
`nav_region: NavigationRegion3D`, `zones: Array[CasinoZone]`, `interactables: Array[Interactable]`, `table_anchors: Array[Dictionary]` (`{id: StringName, game_type: int, area_id: StringName, transform: Transform3D}`), `spawn_points: Array[Vector3]` (entrance), `curb_point: Vector3`, `back_room_point: Vector3` (guards carry players here), `back_room_release_point: Vector3`, `exit_point: Vector3`, `patrol_routes: Array` (one `Array[Vector3]` per floor guard; at least `casino.guards`), `pit_boss_posts: Array[Vector3]`, `camera_mounts: Array[Transform3D]`, `patron_points: Array[Vector3]`, `slot_seats: Array[Transform3D]`, `forger_points: Dictionary` (`&"parking_garage"|&"restroom"|&"loading_dock"` → `Vector3`), `poster_boards: Array[PosterBoardNode]`; `bake_navigation() -> void`.

`PosterBoardNode extends Node3D`: `board_id: StringName` (`&"entrance"|&"cashier"|&"security_desk"`), `show_posters(posters: Array) -> void` (array of `WantedPoster.to_dict()`-style dicts; draws outfit color swatches + "WANTED"), each poster gets an `Interactable` kind `&"poster"` with `data.poster_id` (hold to tear, press to deface).

`CharacterModel extends Node3D` (`scripts/world/character_model.gd`): `apply_outfit(outfit: Outfit)`, `apply_uniform(kind: StringName)` (`&"guard"`, `&"pit_boss"`, `&"head_of_security"`, `&"dealer"`, `&"staff"`), `set_pose(pose: StringName)` (`&"idle"`, `&"walk"`, `&"run"`, `&"sit"`, `&"play"`, `&"celebrate"`, `&"carried"`, `&"carry"`, `&"tackle"`, `&"dive"`, `&"tumble"`, `&"jump"`), `set_highlight(color: Color)` (null-ish = off). About 1.8 m tall, feet at origin, faces −Z.

`PlayerCharacter extends CharacterBody3D` (`scripts/world/player_character.gd`, layer 2): `setup(pid: int, is_local: bool, outfit: Outfit)`, `pid`, `model: CharacterModel`, third-person camera rig (only when local); `is_running() -> bool`, `sit_at(seat: Transform3D)`, `stand_up()`, `set_carried(carrier: Node3D)` (follows `carrier.get_carry_point()` until `release(at: Vector3)`), `teleport(pos: Vector3)`, `set_outfit(outfit: Outfit)`, `set_input_enabled(enabled: bool)` (UI panels open), `set_hidden(hidden: bool)`, `tumble()`. Signals: `interact_pressed(target: Interactable)`, `interact_held(target: Interactable)` (after `hold_seconds`), `tackle_requested(target: Node3D)` (F or dive near a guard within `TACKLE_RANGE`), `bumped(guard: Node3D)` (ran into a guard), `throw_chips_requested(position: Vector3)`, `knock_over_requested(target: Interactable)`, `struggled()` (jump while carried), `pause_requested()`.

`GuardNPC extends CharacterBody3D` (`scripts/world/guard_npc.gd`, layer 3): `setup(guard_id: int, security_type: int, patrol: Array[Vector3], back_room: Vector3, players_provider: Callable)` where `players_provider.call() -> Array` of `{pid, node: Node3D, heat: float, matches_poster: bool, staff_uniform: bool, available: bool}`; owns a `GuardBrain` and `NavigationAgent3D`; sees with `Perception.in_vision_cone` + a world-layer raycast; `hear(noise: Dictionary)` (`{position, radius, kind}`), `set_id_check_result(pid: int, passed: bool)`, `stun()`, `on_struggle()`, `alert(pid: int, position: Vector3)` (pit boss radio), `set_fire_alarm(active: bool)`, `get_carry_point() -> Vector3`, `carrying_pid() -> int`. Signals: `saw_player(guard, pid: int, running: bool)` (each physics frame a player is visible), `id_check_requested(guard, pid)`, `grabbed(guard, pid)`, `delivered(guard, pid)` (reached back room), `released(guard, pid)` (stunned while carrying), `state_changed(guard, old, new)`. Shows a floor vision cone tinted by state and an icon above the head. Pit boss: stands at a post, raises gains (`pit_boss_view` flag) and emits `radioed(guard, pid, position)` on a Suspected player. Undercover wears a patron outfit. Head of security is faster.

`SecurityCamera extends Node3D`: `setup(camera_id: int, mount: Transform3D, players_provider: Callable)`; sweeping cone with LOS; signals `watching(camera, pid: int, active: bool)`, `spotted(camera, pid: int)`.

`PatronCrowd extends Node3D`: `setup(points: Array[Vector3], slot_seats: Array[Transform3D], count: int, rng_seed: int)`; low-rate wandering `Patron` bodies (layer 4) in random outfits, some seated at slots; `rush_to(position: Vector3, radius: float, seconds: float)` for thrown chips.

`TableNode extends Node3D` (`scripts/world/table_node.gd`): `setup(table_id: StringName, game_type: int, area_id: StringName, rung: int)`; builds the per-game prop (slot cabinet, high-low card table, upright big wheel, dice table, roulette table, blackjack half-moon) with a dealer `CharacterModel` where relevant and a `Label3D` with `TableGames.display_name`; `interactable: Interactable` (kind `&"table"`, `data.table_id`); `seat_transform() -> Transform3D`; `play_result(result: Dictionary, duration: float)` animates `BetResult.to_dict()` (reels, wheel to segment, dice to faces, ball to number, cards); `show_hand(state: Dictionary)` for high-low/blackjack in progress; `dealer_swap()`; `set_closed(closed: bool)`; `flash_loud()`; `signal result_shown(table_id)`.

`SimHost extends Node` (`scripts/world/sim_host.gd`): owns `run: RunState` and the current `sim: FloorSim`; `start_run(start_rung: int, seed: int, player_names: Dictionary)`, `start_visit() -> FloorSim` (new FloorSim each visit, carrying PlayerStates), ticks the sim in `_physics_process`; `signal sim_event(kind: StringName, data: Dictionary)` re-emits every FloorSim event; one `request_<name>(...)` method per FloorSim request with the same arguments and return value. This is the phase-2 RPC boundary.

UI (`scripts/ui/`): `Hud`, `BetPanel`, `IdQuizPanel`, `CashierPanel`, `WardrobePanel` (restroom stash + gift shop), `ForgerPanel`, `TitleScreen`, `PauseMenu`, `VisitBanner` (thrown out / climbed), `DebugOverlay`. Each is a `Control` built in code with `setup(host: SimHost, pid: int)`, listens to `host.sim_event`, calls `host.request_*`, and emits `closed()` when a modal panel closes.

`CasinoDirector extends Node3D` (`scripts/world/casino_director.gd`): one per visit; builds the map, spawns and wires everything above, provides `players_provider`, forwards noises to guards in earshot, updates poster boards, and emits `visit_finished(outcome: StringName)`. `main.gd` owns `SimHost`, the UI and the title/pause flow, and swaps directors between visits.

## Tests

`./tools/test.sh` copies the project to a temp dir, imports it, then runs `tests/run_tests.gd`, which runs every `test_*` method in `tests/unit/test_*.gd` and `tests/integration/test_*.gd`. Tests extend `TestCase` (assert helpers in `tests/test_case.gd`) and may `await tree.process_frame`. Any `SCRIPT ERROR` in the output fails the run.
