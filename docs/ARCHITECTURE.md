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
- `static func passive_rate(ctx: Dictionary) -> float` — Heat per second from the current situation. Keys (all optional): `seated_game: int` (−1 = not seated), `seconds_at_table: float`, `zone: int` (`HR.ZoneType`), `running_in_view: bool`, `in_camera_view: bool`, `heat: float` (cameras only add Heat from Watched up — "Watched: cameras follow you"; without the key the camera always counts). Covers camping, slot blend, off-table zones, floor decay, running and cameras.
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
- `casino() -> Dictionary`, `add_bank(amount)` (at the top rung it goes to `top_banked`, otherwise to `bank`), `withdraw(amount) -> bool` (takes chips back out of `bank`, never `top_banked`), `add_strike() -> bool` (true when it hits `Tuning.STRIKES_TO_THROW_OUT`), `throw_out(to_rung: int = -1) -> int` (drops a rung — or to `to_rung` — resets strikes and per-visit state; at the bottom it's a curb timeout and the rung stays), `can_climb() -> bool`, `climb() -> int` (spends the buy-in(s) from `bank`), `tick(delta)`, `score() -> int` (`top_banked + floor(top_seconds / 60) × Tuning.SCORE_PER_MINUTE_AT_TOP`).

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

`FloorSim` is the single host-authoritative object for one casino visit; `RunState` persists across visits. World and UI code never change chips, Heat, IDs or outfits: they call requests (through `SimHost`) and react to events.

**`class_name PlayerState`** (read-only outside FloorSim). Carried from visit to visit by the next FloorSim, which keeps pocket, outfit, stash and IDs and resets the rest (`begin_visit()`).
- `pid: int`, `display_name: String`, `heat: HeatMeter`, `wallet: Wallet`, `outfit: Outfit`, `stash: Array[Outfit]`, `ids: Array[FakeId]`, `id_index: int` (−1 = none), `status: int` (`HR.PlayerStatus`), `zone: int` (`HR.ZoneType`, starts `ENTRANCE`), `area_id: StringName`, `table_id: StringName` (`&""` standing), `recorded_look: Outfit` (copied on reaching Suspected in this casino; null if none), `flags: Dictionary` (`running_in_view`, `in_camera_view`, `pit_boss_view`), `outfit_changes: int`, `high_low: HighLowRun` / `blackjack: BlackjackRound` (round in progress or null).
- Timers and bookkeeping (FloorSim only): `status_seconds` (left of DETAINED / ON_CURB), `last_table_id`, `seconds_since_left_table`, `last_game_area`, `seconds_since_area_change`, `seconds_unseen`, `poster_match_armed`, `poster_armed`, `id_question`, `id_check_guard`, `id_check_seconds`, `steal_cooldown`, `round_table_id`.
- `current_id() -> FakeId` (or null), `has_usable_id() -> bool`, `first_usable_id_index() -> int`, `is_available() -> bool` (FREE, SEATED or ID_CHECK: on the floor and grabbable), `can_act() -> bool` (FREE or SEATED), `in_round() -> bool`, `round_kind() -> StringName` (`&"high_low"`, `&"blackjack"`, `&""`), `level() -> int`, `stash_dicts() -> Array`, `id_dicts() -> Array`, `begin_visit()`, `release_listeners()`, `reset_flags()`.

**`class_name FloorSim`**
- `signal event(kind: StringName, data: Dictionary)` — everything goes out through this one signal (kinds below). Event data is plain (int, float, String, StringName, Vector3, Dictionary, Array), never an Object, so it can go over RPC. A quiz's `correct_index` never leaves the host.
- `var run: RunState`, `rng: RandomNumberGenerator`, `players: Dictionary` (pid → PlayerState, join order), `tables: Dictionary` (id → TableState), `forger: Forger` (starts at a random spot), `finished: bool`, `outcome: StringName` (`&"thrown_out"` / `&"climbed"` once finished), `last_reason: StringName` (why the last `start_*` returned null), `fire_alarm_seconds: float` (> 0 while active), `slot_alarm_cooldown: float`, `broke_seconds: float` (how long a broke crew has been on the floor, see "Crew outcomes").
- Setup:
  - `_init(run: RunState, seed: int, carried_players: Array = [])` — a new visit. Carried PlayerStates are detached from the previous FloorSim, `begin_visit()`-reset (FREE at ENTRANCE, Heat 0, no recorded look, timers cleared) and given a usable ID (switches to a held card that passes a check, else a free `Tuning.REJOIN_ID_GRADE` card).
  - `add_player(pid: int, display_name: String) -> PlayerState` — `Tuning.START_CHIPS`, a random outfit, one `Tuning.START_ID_GRADE` (solid) ID in use, `Tuning.START_STASH_OUTFITS` (2) random stash outfits. Returns the existing player for a known pid. Emits `player_joined`.
  - `register_table(id: StringName, game_type: int, area_id: StringName, position: Vector3 = ZERO) -> TableState` — the director registers every table (including slot machines) after building the map; `position` is where its noises come from. Returns the existing table for a known id. Starts closed during a fire alarm.
- `tick(delta: float)` — run clock, tables, forger, fire-alarm and slot-alarm timers, per-player timers (detention, curb, ID-quiz timeout, poster re-arm, steal cooldown) and passive Heat (`HeatRules.passive_rates` per reason, pit-boss multiplier on gains) for FREE/SEATED/ID_CHECK players; at Sal's, the broke-crew bailout. Does nothing once `finished`.

**Requests.** Every request returns a Dictionary with at least `ok: bool` and `reason: StringName` (`&""` on success) plus the keys listed, and never throws: unknown pid/table, negative amounts, bad indices or kinds give `ok: false`. Failure-only keys are filled with neutral values. After `finished` every request fails with `&"finished"`. `start_high_low`/`start_blackjack` return the round object (read it, never call its methods — use the wrappers) or null with the reason in `last_reason`.

| Request | Extra result keys | Rules |
| --- | --- | --- |
| `sit(pid, table_id: StringName, in_view: bool = false)` | `table_id, game_type, heat` | FREE or SEATED; stands up from another table first (settling its round); refuses closed tables and staff uniforms. Leaving another table under `TABLE_JUMP_WINDOW` s ago with `in_view` (a guard sees it) adds `TABLE_JUMP` Heat (`heat`). Sitting again where you sit is a no-op. |
| `stand(pid)` | `table_id` | Settles a round in progress (high-low cashes out, blackjack stands). |
| `place_bet(pid, table_id, amount: int, choice: Dictionary = {})` | `result` (BetResult dict), `pocket` | Slots, big wheel, dice, roulette only (`wrong_game` for high-low/blackjack). Must be SEATED at that table, no round in progress, table open, `min_bet ≤ amount ≤ max_bet` of the casino, `amount ≤ pocket`. `choice` as `GameResolver.resolve` (`throw`, roulette `kind`/`color`/`number`, dice `call`). Dice solo is a one-bettor shared roll. |
| `place_shared_roll(table_id, bets: Array)` | `results` (pid → BetResult dict), `rejected` (pid → reason) | Dice table only. `bets` items `{pid, bet, throw?, call?}`, each validated like `place_bet`; invalid ones are left out. Fails (with the first rejection reason, or `no_bets`) only if none is valid. Win Heat reason `SHARED_ROLL` with 2+ bettors. |
| `start_high_low(pid, table_id, bet) -> HighLowRun` | — | Validated like `place_bet` at a high-low table; the stake leaves the pocket now. Emits `hand`. |
| `high_low_guess(pid, higher: bool, throw: bool = false)` | `result, won, pot, card, finished, pocket` | SEATED (not mid ID check). Win Heat per winning guess; a wrong guess ends the run (pot lost). |
| `high_low_cash_out(pid)` | `result, payout, pocket` | Pot into the pocket; run over. |
| `start_blackjack(pid, table_id, bet) -> BlackjackRound` | — | As `start_high_low` at a blackjack table. |
| `blackjack_hit(pid)` | `card, total, finished, result` (`{}` until finished), `pocket` | Busting ends the hand; hitting past 21 is a thrown hand (`LOSE_ON_PURPOSE` Heat). |
| `blackjack_stand(pid)` | `result, pocket` | Dealer plays out; hand settles. |
| `enter_zone(pid, zone: int, area_id: StringName)` | `heat` | Any status; records the zone. Entering a TABLES/SLOTS area different from the last one gives `AREA_CHANGE` cool-off (at most once per `AREA_CHANGE_COOLDOWN`, only while available). |
| `set_player_flags(pid, flags: Dictionary)` | `flags` | Keys `running_in_view`, `in_camera_view`, `pit_boss_view` (bools; missing keys keep their value). Drives passive Heat and the pit-boss gain multiplier. Call when they change. |
| `report_seen(pid, ctx: Dictionary = {})` | `matches_poster, recognized, poster_id` (−1), `heat` | A guard sees the player this frame; ctx `{guard_id: int, pit_boss: bool}`. `matches_poster`: a poster in this casino recognizes the worn outfit; `recognized`: the worn outfit matches `recorded_look`. A match adds `POSTER_MATCH_HEAT` (× pit-boss multiplier when `pit_boss`) once per sighting; it re-arms after `POSTER_MATCH_REARM_SECONDS` unseen or an outfit change. |
| `change_to_stash(pid, index: int)` | `outfit, heat` | FREE in a RESTROOM zone. Swaps the worn outfit with `stash[index]`; `CHANGE_OUTFIT_HEAT`. |
| `change_outfit(pid, outfit: Variant)` | `outfit, heat` | FREE in a RESTROOM. `outfit` is an `Outfit` or its `to_dict()`. Every piece must fit its slot and be owned (worn now or in any stash outfit; `none` allowed in optional slots) — mix and match. The old look goes into the stash (unless an equal one is there); an equal stash outfit is taken out. `CHANGE_OUTFIT_HEAT`. |
| `buy_outfit_piece(pid, slot: int, piece_id: StringName)` | `price, stash_index, outfit` | FREE in a GIFT_SHOP zone; piece for sale and fits the slot; not already worn there. **Not worn right away:** the stash gains a copy of the worn outfit with that piece (change into it at a restroom). |
| `steal_outfit_piece(pid)` | `uniform, slot` (−1 for the uniform), `piece, stash_index, outfit` | FREE in a STAFF_ONLY zone (laundry cart / staff locker); per-player `STEAL_COOLDOWN` (`seconds` on `cooldown`). `STEAL_UNIFORM_CHANCE` of the full staff uniform, else one random civilian piece on a copy of the worn outfit; lands in the stash. |
| `buy_id(pid, grade: int)` | `price, id, index` | FREE in a FORGER zone whose `area_id == forger.location()` (`forger_not_here` otherwise). The new card is put in use. |
| `swap_id(pid, index: int)` | `id, index` | FREE or SEATED (not mid-check). |
| `start_id_check(pid, guard_id: int = -1)` | `auto_fail, fail_reason, question` (`{field, prompt, options}` or `{}`), `seconds` | FREE or SEATED. Auto-fails on the spot (`id_check` then `id_result`, status unchanged) with no card (`no_id`), a burned (`burned`) or flagged (`flagged`) card, or a cheap card spotted on sight (`spotted`). Otherwise status ID_CHECK with an `IdQuiz` question for `ID_QUIZ_SECONDS`; the sim expires it itself `ID_QUIZ_GRACE_SECONDS` later. |
| `answer_id_check(pid, option_index: int)` | `passed` | Ends the check (`id_result` reason `correct`/`wrong`); back to SEATED if still seated, else FREE. `no_question` if none pending. |
| `expire_id_check(pid)` | `passed` (false) | The UI timer ran out: a fail (`timeout`). |
| `tear_poster(pid, poster_id: int, position: Vector3 = ZERO)` | `poster_id` | FREE; poster up in this casino. Removes it; noisy (`tear_poster`). |
| `deface_poster(pid, poster_id: int, slot: int = -1)` | `slot, poster` | FREE; poster in this casino. `slot` −1 picks the first readable slot matching the player's worn piece (else the first readable). `no_slot` if none left / already defaced. |
| `caught(pid, guard_id: int = -1)` | — | Player available. Drops any ID check, stands up (round settles), CARRIED. Struggling is world-side. If every player is CARRIED/DETAINED and the crew has at least `CREW_WIPE_MIN_PLAYERS` (2) players, the crew is thrown out. |
| `freed(pid, tackler_pid: int = 0)` | — | `pid` CARRIED → FREE. `tackler_pid > 0`: an available teammate tackled the guard and goes straight to Wanted (`raise_to(WANTED_AT, TACKLE)`, which prints their poster). `0`: the guard let go by itself (stunned, fire alarm). |
| `reach_back_room(pid)` | `chips_lost, strikes, thrown_out, curb` | CARRIED only. Pocket lost, current ID burned, Heat reset, crew strike, DETAINED for `BACK_ROOM_TIMEOUT` then `rejoined` (FREE on the FLOOR, with a usable ID: a held one, else a free cheap one). Third strike or a crew wipe throws the crew out (`thrown_out`), or at Sal's puts it on the curb (`curb`). |
| `withdraw(pid, amount: int)` | `amount, pocket, bank` | FREE in a CASHIER zone; `0 < amount ≤ run.bank` (`bad_amount`, `not_enough`). Moves crew-bank chips into the pocket (never `top_banked`, the score); no ID needed, no Heat. Event `withdrawn`. |
| `cash_out(pid, amount: int)` | `banked, heat, flagged, bank, top_banked` | FREE in a CASHIER zone. `Cashier.cash_out` with the current ID (`bad_id`, `bad_amount`, `not_enough` pass through). Banked chips → `run.add_bank` (score at the top rung). Large cash-out Heat (`CASH_OUT`). Crossing the ID's cap flags it: `id` + `notify` (`flagged`). |
| `distraction(pid, kind: int, position: Vector3 = ZERO)` | `kind, cost, heat` | FREE or SEATED. `HR.Distraction`: `THROW_CHIPS` costs `max(THROW_CHIPS_MIN, floor(pocket × THROW_CHIPS_FRACTION))`, `noise` + `crowd_rush`; `KNOCK_OVER` `KNOCK_OVER_HEAT` + noise; `BUMP_GUARD` `BUMP_GUARD_HEAT` + noise; `SLOT_ALARM` crew-wide `SLOT_ALARM_COOLDOWN` (`cooldown` with `seconds`) + big noise; `FIRE_ALARM` once per visit (`used`), closes every table for `FIRE_ALARM_SECONDS` and stands everyone up. `WIN_BIG` and unknown kinds: `bad_kind`. |
| `give_chips(from_pid, to_pid, amount: int)` | `from_pocket, to_pocket` | Both FREE or SEATED; amount > 0. Proximity is world-side. |
| `try_climb()` | `from, to, cost, missing` (pids not at the exit) | `run.can_climb()` (`cant_climb`), and every player who isn't DETAINED is FREE in an EXIT zone (`not_at_exit`). Climbs one rung, or two by the stretch rule, spending the buy-in; the visit ends (`climbed`). Call it when someone reaches the exit. |

Reasons are `FloorSim` constants: `NO_REASON` (`&""`), `FINISHED`, `UNKNOWN_PLAYER`, `UNKNOWN_TABLE`, `BUSY` (status doesn't allow it), `WRONG_ZONE`, `BAD_AMOUNT`, `NOT_ENOUGH`, `BELOW_MIN`, `ABOVE_MAX`, `TABLE_CLOSED`, `NOT_SEATED`, `WRONG_GAME`, `IN_ROUND`, `NO_ROUND`, `STAFF_UNIFORM`, `NO_BETS`, `BAD_INDEX`, `BAD_OUTFIT`, `NOT_OWNED`, `SAME_OUTFIT`, `BAD_PIECE`, `ALREADY_WEARING`, `COOLDOWN`, `FORGER_NOT_HERE`, `BAD_GRADE`, `NO_QUESTION`, `NOT_AVAILABLE`, `NOT_CARRIED`, `SAME_PLAYER`, `BAD_KIND`, `USED`, `CANT_CLIMB`, `NOT_AT_EXIT`, `UNKNOWN_POSTER`, `NO_SLOT`; plus `Cashier.BAD_ID` / `BAD_AMOUNT` / `NOT_ENOUGH` from `cash_out`. ID-check reasons: `ID_CORRECT` (`&"correct"`), `ID_WRONG`, `ID_TIMEOUT`, `ID_NONE` (`&"no_id"`), `ID_BURNED`, `ID_FLAGGED`, `ID_SPOTTED`.

**Heat rules applied by the sim.** Every BetResult's Heat is applied once via `HeatMeter.add` (`WIN`, `SHARED_ROLL` for crew rolls, `LOSE_ON_PURPOSE` for thrown losses), and every positive gain is multiplied by `PIT_BOSS_HEAT_MULT` while the player's `pit_boss_view` flag is set. Level crossings upward: reaching **Watched** while seated cools that table for them (`TableState.mark_cooled`, win rate `COOLED_WIN_RATE` until they leave) + `dealer_swap`; reaching **Suspected** copies the worn outfit to `recorded_look` + `look_recorded`; reaching **Wanted** prints a poster of the worn outfit in this casino (`run.posters`) + `poster`, once per Wanted episode (re-arms after dropping below Wanted). Loud results (big wheel, slot jackpot) emit `noise` at the table's position.

**Crew outcomes.** Three strikes (`STRIKES_TO_THROW_OUT`), or a whole crew of 2+ held at once: above Sal's the crew is thrown out — `run.throw_out()`, `finished = true`, `outcome = &"thrown_out"`, event `thrown_out`; start the next visit with `SimHost.start_visit()`. At Sal's (bottom rung) it is a curb timeout instead: `run.throw_out()` (rung stays, strikes and fire alarm reset), every player ON_CURB for `CURB_TIMEOUT` with Heat reset, event `curb` (no `thrown_out`), then `rejoined` at the ENTRANCE; the visit goes on. A solo player is only thrown out by strikes, or by going broke. A broke crew (every pocket and the bank under the min bet, no round in progress): at Sal's it gets `BAILOUT_CHIPS` each + `notify` (`bailout`); above Sal's and below the top (where the exit always ends the run) it gets a `notify` (`broke`) and, after `Tuning.BROKE_GRACE_SECONDS` with nobody carried or detained, is thrown out (cause `&"broke"`) to the highest rung below where the bank covers a bet (Sal's at worst). A crew with bank chips is never broke: it can `withdraw` them.

**Events** (`kind` → data keys). Typical order for a bet: `chips` (stake), `chips` (payout on a win), `bet`, `heat`, `level`…, then `dealer_swap` / `look_recorded` / `poster`, then `noise`.

| Kind | Data |
| --- | --- |
| `player_joined` | `pid, name` |
| `status` | `pid, status, old` (`HR.PlayerStatus`, on every change) |
| `seated` / `stood` | `pid, table_id` (+ `game_type` on `seated`) |
| `zone` | `pid, zone, area_id` (when it changes) |
| `bet` | `pid, table_id, game_type, result` (BetResult.to_dict(): animate with `TableNode.play_result`), `pocket`, `round_over` (false for a winning high-low guess) |
| `hand` | `pid, table_id, game_type, state` — high-low `{kind: &"high_low", bet, pot, card, streak, finished}`; blackjack `{kind: &"blackjack", bet, player_cards, dealer_cards` (up card only), `player_total, finished}`. Sent on start, after each winning guess and after each non-busting hit. |
| `heat` | `pid, value, delta, reason, level` — every change, including passive ones every tick (reasons `camping`, `slot_blend`, `off_table`, `floor_decay`, `run_in_view`, `camera`); filter those for popups. |
| `level` | `pid, old, new, name` (one event per level boundary crossed) |
| `dealer_swap` | `pid, table_id` |
| `look_recorded` | `pid, outfit` (dict) |
| `poster` | `pid, casino_id, poster` (WantedPoster.to_dict()) |
| `poster_match` | `pid, poster_id, guard_id, pit_boss` |
| `poster_removed` | `poster_id, casino_id` |
| `poster_defaced` | `poster_id, slot, casino_id, poster` |
| `chips` | `pid, pocket, delta` (every pocket change) |
| `chips_given` | `from, to, amount` |
| `banked` | `pid, amount, bank, top_banked, flagged, id_name` |
| `withdrawn` | `pid, amount, bank` |
| `outfit` | `pid, outfit` (worn, dict), `stash` (array of dicts), `worn_changed` (true: re-dress the model), `reason` (`&"restroom"`, `&"bought"`, `&"stolen"`) |
| `id` | `pid, id` (FakeId.to_dict() of the card in use, or `{}`), `index, count, reason` (`&"bought"`, `&"swapped"`, `&"burned"`, `&"flagged"`, `&"rejoin"`, `&"auto_swap"`) |
| `id_check` | `pid, guard_id, auto_fail, fail_reason, question` (`{field, prompt, options}` or `{}`), `seconds` |
| `id_result` | `pid, guard_id, passed, reason` (route to `GuardNPC.set_id_check_result`) |
| `caught` | `pid, guard_id` |
| `freed` | `pid, tackler` (0 = the guard let go) |
| `detained` | `pid, chips_lost, id_burned, id_name, seconds` |
| `strike` | `pid, strikes, max` |
| `rejoined` | `pid, from` (`&"back_room"` → FLOOR, release point; `&"curb"` → ENTRANCE), `new_id` |
| `curb` | `rung, seconds, cause` |
| `thrown_out` | `from, to, cause` (`&"strikes"`, `&"crew_detained"`, `&"broke"`) |
| `climbed` | `from, to, cost` |
| `noise` | `position: Vector3, radius, kind, pid` — kinds `big_wheel`, `slot_jackpot` (jackpot or tripped alarm), `throw_chips`, `knock_over`, `bump`, `fire_alarm`, `tear_poster`; radius from `Tuning.NOISE_RADIUS` |
| `crowd_rush` | `pid, position, radius, seconds` (→ `PatronCrowd.rush_to`) |
| `fire_alarm` | `active, seconds, pid` (on start and end) |
| `forger_moved` | `location` |
| `notify` | `pid` (0 = whole crew), `text, kind` (`&"flagged"`, `&"bailout"`, `&"broke"`) |

**Queries:** `player(pid) -> PlayerState` (or null), `player_ids() -> Array[int]`, `table(id) -> TableState` (or null), `casino() -> Dictionary` (Tuning.CASINOS row copy), `score() -> int`, `fire_alarm_active() -> bool`, `matches_poster(pid) -> bool`, `posters_here() -> Array` (WantedPoster dicts up in this casino), `snapshot() -> Dictionary`:
- `players`: pid → `{pid, name, heat, level, pocket, lifetime_banked, status, status_seconds, zone, area_id, table_id, round` (`&"high_low"`/`&"blackjack"`/`&""`), `outfit` (dict), `stash` (array of dicts), `stash_size, id` (dict or `{}`), `id_index, ids` (array of dicts), `id_count, id_check` (pending `{field, prompt, options}` or `{}`), `recorded_look` (dict or `{}`), `recognized, matches_poster, staff_uniform, available, flags}`
- `run`: `{rung, casino_id, casino_name, min_bet, max_bet, strikes, max_strikes, bank, buy_in` (to climb one rung; 0 at the top), `stretch_buy_in` (to skip a rung; 0 if impossible), `climb_target, can_climb, top_banked, score, top_seconds, visit_seconds, elapsed_seconds, visits, fire_alarm_used, is_top, is_bottom}`
- `tables`: id → `{game_type, area_id, closed, seated: [pids]}`
- `fire_alarm: bool`, `fire_alarm_seconds`, `slot_alarm_cooldown`, `forger_location: StringName`, `forger_seconds_until_move`, `posters` (as `posters_here()`), `finished`, `outcome`.

**Wiring hints for the director.** Table interactable → `request_sit(pid, id, guard_sees_player)`; `CasinoZone.player_entered` → `request_enter_zone`; per frame (on change) `request_set_player_flags`; `GuardNPC.saw_player` → `request_report_seen(pid, {guard_id, pit_boss})` (its `matches_poster` feeds `players_provider`); `id_check_requested` → `request_start_id_check(pid, guard_id)` and `id_result` → `set_id_check_result`; `grabbed` → `request_caught`; `delivered` → `request_reach_back_room`; `released` → `request_freed(pid, 0)`; a player's tackle on a carrying guard → stun it + `request_freed(carried_pid, tackler_pid)`; `bumped` → `request_distraction(pid, BUMP_GUARD, pos)`; `noise` → `hear()` on guards in radius; `bet` → `TableNode.play_result`; `hand` → `show_hand`; `dealer_swap` → `dealer_swap()`; `fire_alarm` → `set_closed` + `set_fire_alarm`; `poster*` → `show_posters(sim.posters_here())`; `outfit` with `worn_changed` → `set_outfit`; `rejoined`/`curb` → teleport; `thrown_out`/`climbed` → `visit_finished(outcome)`.

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
`nav_region: NavigationRegion3D`, `zones: Array[CasinoZone]`, `interactables: Array[Interactable]`, `table_anchors: Array[Dictionary]` (`{id: StringName, game_type: int, area_id: StringName, transform: Transform3D}`), `spawn_points: Array[Vector3]` (entrance), `curb_point: Vector3`, `back_room_point: Vector3` (guards carry players here), `back_room_release_point: Vector3`, `exit_point: Vector3`, `patrol_routes: Array` (one `Array[Vector3]` per floor guard; at least `casino.guards`), `pit_boss_posts: Array[Vector3]`, `camera_mounts: Array[Transform3D]`, `patron_points: Array[Vector3]`, `slot_seats: Array[Transform3D]`, `forger_points: Dictionary` (`&"parking_garage"|&"restroom"|&"loading_dock"` → `Vector3`), `poster_boards: Array[PosterBoardNode]`; `bake_navigation() -> void`; `reset_zone(player)` (forget the zone a player counts as in, so it is announced again — after the sim moved the player itself, e.g. a rejoin). Zone-gated interactables (cashier, gift shop, exit, the forger NPC's) are small enough that the player's 1.5 m sensor only reaches them from inside the zone their request needs.

`PosterBoardNode extends Node3D`: `board_id: StringName` (`&"entrance"|&"cashier"|&"security_desk"`), `show_posters(posters: Array) -> void` (array of `WantedPoster.to_dict()`-style dicts; draws outfit color swatches + "WANTED"), each poster gets an `Interactable` kind `&"poster"` with `data.poster_id` (hold to tear, press to deface).

`CharacterModel extends Node3D` (`scripts/world/character_model.gd`): `apply_outfit(outfit: Outfit)`, `apply_uniform(kind: StringName)` (`&"guard"`, `&"pit_boss"`, `&"head_of_security"`, `&"dealer"`, `&"staff"`), `set_pose(pose: StringName)` (`&"idle"`, `&"walk"`, `&"run"`, `&"sit"`, `&"play"`, `&"celebrate"`, `&"carried"`, `&"carry"`, `&"tackle"`, `&"dive"`, `&"tumble"`, `&"jump"`), `set_highlight(color: Color)` (null-ish = off). About 1.8 m tall, feet at origin, faces −Z.

`PlayerCharacter extends CharacterBody3D` (`scripts/world/player_character.gd`, layer 2): `setup(pid: int, is_local: bool, outfit: Outfit)`, `pid`, `model: CharacterModel`, third-person camera rig (only when local); `is_running() -> bool`, `sit_at(seat: Transform3D)`, `stand_up()`, `set_carried(carrier: Node3D)` (follows `carrier.get_carry_point()` until `release(at: Vector3)`), `teleport(pos: Vector3)`, `set_outfit(outfit: Outfit)`, `set_input_enabled(enabled: bool)` (UI panels open), `set_hidden(hidden: bool)`, `tumble()`. Signals: `interact_pressed(target: Interactable)`, `interact_held(target: Interactable)` (after `hold_seconds`), `tackle_requested(target: Node3D)` (F or dive near a guard within `TACKLE_RANGE`), `bumped(guard: Node3D)` (ran into a guard), `throw_chips_requested(position: Vector3)`, `knock_over_requested(target: Interactable)`, `struggled()` (jump while carried), `pause_requested()`.

`GuardNPC extends CharacterBody3D` (`scripts/world/guard_npc.gd`, layer 3): `setup(guard_id: int, security_type: int, patrol: Array[Vector3], back_room: Vector3, players_provider: Callable)` where `players_provider.call() -> Array` of `{pid, node: Node3D, heat: float, matches_poster: bool, staff_uniform: bool, available: bool}`; owns a `GuardBrain` and `NavigationAgent3D`; sees with `Perception.in_vision_cone` + a world-layer raycast; `hear(noise: Dictionary)` (`{position, radius, kind}`), `set_id_check_result(pid: int, passed: bool)`, `stun()`, `on_struggle()`, `alert(pid: int, position: Vector3)` (pit boss radio), `set_fire_alarm(active: bool)`, `get_carry_point() -> Vector3`, `carrying_pid() -> int`. Signals: `saw_player(guard, pid: int, running: bool)` (each physics frame a player is visible), `id_check_requested(guard, pid)`, `grabbed(guard, pid)`, `delivered(guard, pid)` (reached back room), `released(guard, pid)` (stunned while carrying), `state_changed(guard, old, new)`. Shows a floor vision cone tinted by state and an icon above the head. Pit boss: stands at a post, raises gains (`pit_boss_view` flag) and emits `radioed(guard, pid, position)` on a Suspected player. Undercover wears a patron outfit. Head of security is faster.

`SecurityCamera extends Node3D`: `setup(camera_id: int, mount: Transform3D, players_provider: Callable)`; sweeping cone with LOS; signals `watching(camera, pid: int, active: bool)`, `spotted(camera, pid: int)`.

`PatronCrowd extends Node3D`: `setup(points: Array[Vector3], slot_seats: Array[Transform3D], count: int, rng_seed: int)`; low-rate wandering `Patron` bodies (layer 4) in random outfits, some seated at slots; `rush_to(position: Vector3, radius: float, seconds: float)` for thrown chips.

`TableNode extends Node3D` (`scripts/world/table_node.gd`): `setup(table_id: StringName, game_type: int, area_id: StringName, rung: int)`; builds the per-game prop (slot cabinet, high-low card table, upright big wheel, dice table, roulette table, blackjack half-moon) with a dealer `CharacterModel` where relevant and a `Label3D` with `TableGames.display_name`; `interactable: Interactable` (kind `&"table"`, `data.table_id`); `seat_transform() -> Transform3D`; `play_result(result: Dictionary, duration: float)` animates `BetResult.to_dict()` (reels, wheel to segment, dice to faces, ball to number, cards); `show_hand(state: Dictionary)` for high-low/blackjack in progress; `dealer_swap()`; `set_closed(closed: bool)`; `flash_loud()`; `signal result_shown(table_id)`.

`SimHost extends Node` (`scripts/world/sim_host.gd`): the phase-2 RPC boundary. `var run: RunState`, `var sim: FloorSim` (current visit), `var paused: bool` (no ticking while true), `var player_names: Dictionary` (pid → name); `start_run(start_rung: int, seed: int, player_names: Dictionary)` (new RunState; no visit yet); `start_visit() -> FloorSim` (a new FloorSim at `run.rung` carrying the previous visit's PlayerStates, adding any new names; registers no tables — the director does after building the map; with no run it starts a default one); `current_sim() -> FloorSim`; `snapshot() -> Dictionary` (`sim.snapshot()`, or `{run: RunState.to_dict()}` / `{}` without a visit); ticks `sim` in `_physics_process` unless `paused` or `sim.finished`. `signal sim_event(kind: StringName, data: Dictionary)` re-emits every event of the current sim (the old sim is disconnected on `start_visit`/`start_run`); `signal visit_started(sim: FloorSim)`. One `request_<name>(...)` per FloorSim request in `SimHost.REQUESTS` with identical arguments, defaults and return values (e.g. `request_place_bet(pid, table_id, amount, choice = {})`, `request_start_blackjack(...) -> BlackjackRound`, `request_register_table(...) -> TableState`); without a visit they return `{ok: false, reason: &"no_sim"}` (null for `start_*` and `register_table`). See "Simulation facade" for every request, result and event.

UI (`scripts/ui/`): `Hud`, `BetPanel`, `IdQuizPanel`, `CashierPanel`, `WardrobePanel` (restroom stash + gift shop), `ForgerPanel`, `TitleScreen`, `PauseMenu`, `VisitBanner` (thrown out / climbed), `DebugOverlay`. Each is a `Control` built in code with `setup(host: SimHost, pid: int)`, listens to `host.sim_event`, calls `host.request_*`, and emits `closed()` when a modal panel closes.

`CasinoDirector extends Node3D` (`scripts/world/casino_director.gd`): one per visit; builds the map, spawns and wires everything above, provides `players_provider`, forwards noises to guards in earshot, updates poster boards, and emits `visit_finished(outcome: StringName)`. `main.gd` owns `SimHost`, the UI and the title/pause flow, and swaps directors between visits.

## Tests

`./tools/test.sh` copies the project to a temp dir, imports it, then runs `tests/run_tests.gd`, which runs every `test_*` method in `tests/unit/test_*.gd` and `tests/integration/test_*.gd`. Tests extend `TestCase` (assert helpers in `tests/test_case.gd`) and may `await tree.process_frame`. Any `SCRIPT ERROR` in the output fails the run.

`Autopilot` (`tools/autopilot.gd`, `extends Node`) is a bot that plays the real game: add it under `scripts/main.gd`'s node and call `setup(main)`; it follows every visit (`visit_begun`). It drives the local `PlayerCharacter` only through input actions (`Input.action_press` on move, run, interact, jump) and the UI panels through their own button methods (`BetPanel.press_main`, `IdQuizPanel.answer`, `CashierPanel.cash_out` / `withdraw`, `WardrobePanel.wear`, `ForgerPanel.buy`, `VisitBanner.handle_key`), never `SimHost.request_*`. Options: `min_play_seconds`, `climb`, `bet_share`, `throw_chance`, `greed` / `greed_heat` (press on through Suspected), `reaction_seconds`, `quiz_accuracy`, `quit_after_seconds`, `echo`, `rng`. Output: `timeline: Array[String]`, `heat_samples`, `stats` (bets, swaps, checks, chases, catches, banked, climbs...), `anomalies` (watchdogs: stuck walking, panels left open, ID checks that never resolve, sim/node state mismatches, guards stuck in CHECK_ID or CHASE, HUD Heat out of step, visits that don't transition) and `summary()`. `main.gd --autopilot [--autopilot-seconds=N] [--speed=N]` runs it from the command line; `tests/integration/test_autopilot.gd` plays a practice run at Sal's to a climb and an Apex run at 8x.
