class_name Tuning
extends RefCounted
## Every starting number from the design doc in one place. All values are
## first guesses to tune in playtests. Read-only from code; never mutate.

# --- Odds -------------------------------------------------------------------
const WIN_RATE := 0.85
## Win rate at a table whose dealer was swapped because you hit Watched there.
const COOLED_WIN_RATE := 0.5

# --- Heat meter -------------------------------------------------------------
const HEAT_MAX := 100.0
const WATCHED_AT := 25.0
const SUSPECTED_AT := 50.0
const WANTED_AT := 80.0

## Base Heat per win by HR.HeatClass, before bet scaling.
const WIN_HEAT := {
	HR.HeatClass.LOW: 3.0,
	HR.HeatClass.MEDIUM: 6.0,
	HR.HeatClass.HIGH: 10.0,
	HR.HeatClass.VERY_HIGH: 24.0,
}
## Win Heat is multiplied by lerp(min, max, bet / max_bet).
const BET_HEAT_SCALE_MIN := 0.5
const BET_HEAT_SCALE_MAX := 1.5
## Extra Heat for each win beyond the first in a streak at one table.
const STREAK_HEAT_STEP := 2.0
## High-low streak Heat "builds fast".
const HIGH_LOW_STREAK_HEAT_STEP := 4.0

## Seated longer than this at one table and Heat starts to climb.
const CAMP_GRACE_SECONDS := 30.0
const CAMP_HEAT_PER_SECOND := 0.5

## Thrown loss at the max bet; a smaller throw cools in proportion to its
## share of the max bet (HeatRules.lose_on_purpose_heat), so min-bet throws
## can't launder a big win's Heat for pocket change.
const LOSE_ON_PURPOSE_HEAT := -10.0
## One-off cool-down for entering a different game area.
const AREA_CHANGE_HEAT := -6.0
const AREA_CHANGE_COOLDOWN := 20.0
## Per second while off the tables in a bar, buffet or restroom.
const OFF_TABLE_HEAT_PER_SECOND := -2.0
## Per second while seated at a slot machine (blending into the crowd).
const SLOT_BLEND_HEAT_PER_SECOND := -1.0
## A machine paying out draws eyes: no slot blend for this long after a win.
## (Max-bet slots plus the odd min-bet throw were heat-neutral forever.)
const SLOT_BLEND_WIN_PAUSE_SECONDS := 6.0
## Per second anywhere else on the floor while not seated.
const FLOOR_DECAY_PER_SECOND := -0.2
## Loitering: a player who hasn't played (sat down or placed a bet) for this
## long gains LOITER_HEAT_PER_SECOND instead of the off-table / floor / slot
## cool-down ("Security notices someone who isn't playing").
const LOITER_GRACE_SECONDS := 45.0
const LOITER_HEAT_PER_SECOND := 0.6
const CHANGE_OUTFIT_HEAT := -15.0
## Changing outfit again within this many seconds still changes the look but
## cools nothing (swapping two stash outfits back and forth was a free reset).
const CHANGE_OUTFIT_COOLDOWN := 30.0

## Per second while running inside a guard's view.
const RUN_IN_VIEW_HEAT_PER_SECOND := 2.0
## Leaving one table and sitting at another within this window, in view.
const TABLE_JUMP_WINDOW := 5.0
const TABLE_JUMP_HEAT := 5.0
const BUMP_GUARD_HEAT := 25.0
const KNOCK_OVER_HEAT := 6.0
const POSTER_MATCH_HEAT := 10.0
## Large cash-out: Heat added per (amount / current max bet) above the threshold.
const LARGE_CASHOUT_BETS := 10.0
const LARGE_CASHOUT_HEAT_PER_BET := 1.0
const LARGE_CASHOUT_HEAT_MAX := 20.0
## Camera cone adds this per second; pit boss view multiplies Heat gains.
const CAMERA_HEAT_PER_SECOND := 1.0
const PIT_BOSS_HEAT_MULT := 1.5

# --- Security ---------------------------------------------------------------
const PLAYER_WALK_SPEED := 3.2
const PLAYER_RUN_SPEED := 6.5
const PLAYER_JUMP_VELOCITY := 5.0
const PLAYER_DIVE_SPEED := 9.0
const GUARD_WALK_SPEED := 2.2
const GUARD_RUN_SPEED := 5.6
const HEAD_OF_SECURITY_RUN_SPEED := 7.0
const GUARD_CARRY_SPEED := 1.8
## Each struggle press while carried slows the guard by this fraction.
const STRUGGLE_SLOW_PER_PRESS := 0.12
const STRUGGLE_MIN_SPEED_MULT := 0.35
const STRUGGLE_RECOVER_PER_SECOND := 0.4

const VISION_RANGE := 14.0
const VISION_FOV_DEGREES := 110.0
const CAMERA_FOV_DEGREES := 50.0
const CAMERA_RANGE := 18.0
## How long a guard remembers a player's Heat after losing sight.
const GUARD_MEMORY_SECONDS := 10.0
const INVESTIGATE_SECONDS := 6.0
const SEARCH_SECONDS := 8.0
const LOSE_SIGHT_TO_SEARCH_SECONDS := 1.5
const GRAB_RANGE := 1.3
const TALK_RANGE := 2.0
const TACKLE_RANGE := 1.8
const STUN_SECONDS := 2.5
const ID_QUIZ_SECONDS := 5.0
const ID_QUIZ_OPTIONS := 3
## A player who walks away from an ID check is chased.
const ID_CHECK_WALKAWAY_DISTANCE := 4.0
## After a failed ID check the guard stands and shouts this long before
## chasing, and can't grab meanwhile: the player gets a head start.
const ID_FAIL_REACTION_SECONDS := 1.2
## A guard walking over to check a Suspected player keeps coming until their
## Heat drops below this (hysteresis below SUSPECTED_AT).
const WALKOVER_RELEASE_AT := 40.0

## Noise radii (metres) by event. Tuning pass: big wheel 30 -> 16 and slot
## jackpot 25 -> 18 (30 m pulled every guard on the Apex floor).
const NOISE_RADIUS := {
	&"knock_over": 10.0,
	&"big_wheel": 16.0,
	&"slot_jackpot": 18.0,
	&"bump": 8.0,
	&"throw_chips": 12.0,
	&"fire_alarm": 1000.0,
	&"tear_poster": 8.0,
}

# --- Crew play --------------------------------------------------------------
const THROW_CHIPS_FRACTION := 0.05
const THROW_CHIPS_MIN := 20
const THROW_CHIPS_BLOCK_SECONDS := 3.0
const THROW_CHIPS_BLOCK_RADIUS := 4.0
const SLOT_ALARM_COOLDOWN := 60.0
const FIRE_ALARM_SECONDS := 15.0
const BACK_ROOM_TIMEOUT := 10.0
## After rejoining (back room or curb) guards leave the player alone this long
## (PlayerState.is_targetable() is false); ends early on sitting down or
## reaching Watched.
const REJOIN_GRACE_SECONDS := 10.0
const CURB_TIMEOUT := 8.0
const STRIKES_TO_THROW_OUT := 3

# --- Identity ---------------------------------------------------------------
## Matching this many of the five outfit slots counts as recognized.
const RECOGNIZE_MATCHES := 3
## Head of security remembers you through this many outfit changes.
const HEAD_MEMORY_OUTFIT_CHANGES := 1
const POSTER_TEAR_SECONDS := 4.0
const POSTER_DEFACE_SECONDS := 1.5
const FORGER_MOVE_SECONDS := 90.0
const ID_GRADES := {
	HR.IdGrade.CHEAP: {"name": "Cheap", "price": 150, "cap": 6000, "spotted_chance": 0.2},
	HR.IdGrade.SOLID: {"name": "Solid", "price": 800, "cap": 25000, "spotted_chance": 0.0},
	HR.IdGrade.FLAWLESS: {"name": "Flawless", "price": 3000, "cap": 80000, "spotted_chance": 0.0},
}

# --- Economy ----------------------------------------------------------------
## Pocket for a new player when a casino row has no start_chips (each
## Tuning.CASINOS row sets its own; this is The Apex's).
const START_CHIPS := 1500
## Given to each player at Sal's when the crew can no longer cover a min bet.
const BAILOUT_CHIPS := 50
const SLOT_JACKPOT_CHANCE := 0.01
const SLOT_JACKPOT_PAYOUT := 20.0
const SCORE_PER_MINUTE_AT_TOP := 1000

## Game table from the design doc. payout is profit as a multiple of the bet.
const GAMES := {
	HR.GameType.SLOTS: {"name": "Slots", "round_seconds": 3.0, "payout": 0.5, "heat_class": HR.HeatClass.LOW, "loud": false},
	HR.GameType.HIGH_LOW: {"name": "High-Low", "round_seconds": 4.0, "payout": 0.5, "heat_class": HR.HeatClass.LOW, "loud": false},
	HR.GameType.BIG_WHEEL: {"name": "Big Wheel", "round_seconds": 5.0, "payout": 2.0, "heat_class": HR.HeatClass.HIGH, "loud": true},
	HR.GameType.DICE: {"name": "Dice", "round_seconds": 6.0, "payout": 1.0, "heat_class": HR.HeatClass.MEDIUM, "loud": false},
	HR.GameType.ROULETTE: {"name": "Roulette", "round_seconds": 8.0, "payout": 1.0, "heat_class": HR.HeatClass.MEDIUM, "loud": false},
	HR.GameType.BLACKJACK: {"name": "Blackjack", "round_seconds": 10.0, "payout": 1.0, "heat_class": HR.HeatClass.MEDIUM, "loud": false},
}
## Roulette single-number bets: high payout and Heat to match.
const ROULETTE_NUMBER_PAYOUT := 8.0
const ROULETTE_NUMBER_HEAT_CLASS := HR.HeatClass.VERY_HIGH

# --- Casino ladder ----------------------------------------------------------
## Index 0 is rung 1 (the top). buy_in is what the crew must bank in the casino
## below to climb into this one. start_chips is each new player's pocket when
## a run starts at this rung (FloorSim.add_player). Bet limits and
## payout_bonus grow going up.
## Tuning pass (seeded solo climb, tests/integration/test_sim_scenarios.gd:
## bet 60% of max every round + 3 s, cool off at the bar on Watched, no
## guards): buy-ins Apex 17000 -> 21000, Grand 6000 -> 7500, Riverboat
## 2000 -> 2500, Rusty 200 -> 100 so that a clean climb lands a little under
## climb_minutes (guards, cameras and walking add the rest); start_chips
## replace the flat START_CHIPS (1500 everywhere made Sal's a 30 s climb).
const CASINOS := [
	{"rung": 1, "id": &"apex", "name": "The Apex", "setting": "Rooftop sky casino, glass and gold",
		"guards": 8, "security": [HR.SecurityType.FLOOR_GUARD, HR.SecurityType.CAMERA, HR.SecurityType.PIT_BOSS, HR.SecurityType.UNDERCOVER, HR.SecurityType.HEAD_OF_SECURITY],
		"start_chips": 1500, "climb_minutes": 0, "buy_in": 21000, "min_bet": 250, "max_bet": 2500, "payout_bonus": 1.5,
		"floor_color": Color("2b2233"), "wall_color": Color("d9b45a"), "accent_color": Color("f5e6b8")},
	{"rung": 2, "id": &"grand_marquee", "name": "The Grand Marquee", "setting": "Classic strip mega-floor",
		"guards": 6, "security": [HR.SecurityType.FLOOR_GUARD, HR.SecurityType.CAMERA, HR.SecurityType.PIT_BOSS, HR.SecurityType.UNDERCOVER],
		"start_chips": 800, "climb_minutes": 10, "buy_in": 7500, "min_bet": 100, "max_bet": 1000, "payout_bonus": 1.4,
		"floor_color": Color("5a1e2c"), "wall_color": Color("c9a227"), "accent_color": Color("ffd166")},
	{"rung": 3, "id": &"riverboat_queen", "name": "The Riverboat Queen", "setting": "Paddle steamer with narrow decks",
		"guards": 4, "security": [HR.SecurityType.FLOOR_GUARD, HR.SecurityType.CAMERA, HR.SecurityType.PIT_BOSS],
		"start_chips": 400, "climb_minutes": 7, "buy_in": 2500, "min_bet": 50, "max_bet": 500, "payout_bonus": 1.3,
		"floor_color": Color("4a3426"), "wall_color": Color("e8dcc0"), "accent_color": Color("b33a3a")},
	{"rung": 4, "id": &"neon_oasis", "name": "Neon Oasis", "setting": "Off-strip 1970s motel casino",
		"guards": 3, "security": [HR.SecurityType.FLOOR_GUARD, HR.SecurityType.CAMERA, HR.SecurityType.PIT_BOSS],
		"start_chips": 200, "climb_minutes": 5, "buy_in": 500, "min_bet": 25, "max_bet": 250, "payout_bonus": 1.2,
		"floor_color": Color("1f3b4d"), "wall_color": Color("ff6fb5"), "accent_color": Color("3ef0d0")},
	{"rung": 5, "id": &"rusty_spur", "name": "The Rusty Spur", "setting": "Desert truck-stop saloon",
		"guards": 2, "security": [HR.SecurityType.FLOOR_GUARD],
		"start_chips": 80, "climb_minutes": 3, "buy_in": 100, "min_bet": 10, "max_bet": 100, "payout_bonus": 1.1,
		"floor_color": Color("6b4a2e"), "wall_color": Color("c27c3e"), "accent_color": Color("e3c08d")},
	{"rung": 6, "id": &"sals_back_room", "name": "Sal's Back Room", "setting": "Basement card room behind a laundromat",
		"guards": 1, "security": [HR.SecurityType.FLOOR_GUARD],
		"start_chips": 50, "climb_minutes": 2, "buy_in": 0, "min_bet": 5, "max_bet": 50, "payout_bonus": 1.0,
		"floor_color": Color("3d4a3a"), "wall_color": Color("8a8f7a"), "accent_color": Color("d6c98f")},
]
const TOP_RUNG := 1
const BOTTOM_RUNG := 6
## Bank this multiple of the buy-in to skip a rung.
const STRETCH_MULT := 2

# --- identity_looks (outfits and wanted posters) ------------------------------
## Gift-shop price of an outfit piece by its catalog tier (index = tier).
## Tier 0 is free / not sold ("none" pieces and staff uniform pieces).
const OUTFIT_TIER_PRICES := [0, 40, 100, 250]

# --- table_games module -----------------------------------------------------
## The bottom this-many rungs reskin the games (coin pusher, scratch cards, bingo, ...).
const TABLE_RESKIN_RUNGS := 2
## Blackjack: when a winning player stands on 18+, the share of hands where the
## dealer busts (otherwise the dealer stands on a lower total).
const BLACKJACK_DEALER_BUST_SHARE := 0.5
## UNUSED (kept so nothing that names it breaks): a reckless-hit threshold
## gave free cooling on pre-rolled losses, so now only hitting past 21 is a
## thrown blackjack hand. Safe to delete once nothing references it.
const BLACKJACK_RECKLESS_HIT_TOTAL := 17

# --- identity_ids (fake IDs, ID quiz, forger) -------------------------------
## Birth years printed on generated IDs (inclusive). Everyone is well over 21.
const ID_BIRTH_YEAR_MIN := 1941
const ID_BIRTH_YEAR_MAX := 2000
## A decoy birthday in the ID quiz is at most this many years off the real one.
const ID_QUIZ_DECOY_YEAR_SPREAD := 6

# --- guards (GuardBrain) ----------------------------------------------------
## A guard waiting at a noise or search spot turns its view around this fast.
const GUARD_LOOK_AROUND_DEGREES_PER_SECOND := 90.0

# --- simulation facade (PlayerState, FloorSim) ------------------------------
## Extra random outfits in a new player's restroom stash.
const START_STASH_OUTFITS := 2
## Grade of the ID every new player starts with.
const START_ID_GRADE := HR.IdGrade.SOLID
## Grade of the free ID handed to a player who rejoins (or starts a visit) holding no usable ID.
const REJOIN_ID_GRADE := HR.IdGrade.CHEAP
## A poster match adds Heat once per sighting; it re-arms after the player has
## gone unseen by every guard this long (or changes outfit).
const POSTER_MATCH_REARM_SECONDS := 10.0
## Chance a laundry cart / staff locker gives the full staff uniform instead of one random piece.
const STEAL_UNIFORM_CHANCE := 0.35
## Seconds before the same player can steal from a cart or locker again.
const STEAL_COOLDOWN := 30.0
## The sim fails an unanswered ID check this long after ID_QUIZ_SECONDS (the UI normally expires it first).
const ID_QUIZ_GRACE_SECONDS := 0.5
## "Whole crew detained at once" throws out only a crew at least this big; a solo player goes by strikes.
const CREW_WIPE_MIN_PLAYERS := 2

# --- character_model / input_setup (world) ----------------------------------
## Seconds a CharacterModel takes to blend from one pose into the next.
const CHARACTER_POSE_BLEND_SECONDS := 0.18
## Walk/run cycle: radians of stride phase per metre moved, capped per second.
const CHARACTER_STRIDE_RADIANS_PER_METER := 3.4
const CHARACTER_MAX_STRIDE_RATE := 20.0
## Whole tumble animation: fall over, lie dazed, get back up.
const CHARACTER_TUMBLE_SECONDS := 1.6
## The head of security is drawn this much bigger than everyone else.
const HEAD_OF_SECURITY_MODEL_SCALE := 1.1
## Gamepad deadzones for the move actions (stick) and everything else.
const INPUT_STICK_DEADZONE := 0.2
const INPUT_BUTTON_DEADZONE := 0.5

# --- player_character / camera_rig (world) ----------------------------------
## Capsule collider (feet at the origin).
const PLAYER_RADIUS := 0.3
const PLAYER_HEIGHT := 1.75
## Ground acceleration and braking (m/s²); the air gets this share of both.
const PLAYER_ACCELERATION := 45.0
const PLAYER_BRAKING := 55.0
const PLAYER_AIR_CONTROL := 0.35
## How fast the model turns to face where it moves (higher snaps faster).
const PLAYER_TURN_SHARPNESS := 14.0
## Falling pulls harder than rising, for a snappy hop.
const PLAYER_FALL_GRAVITY_MULT := 1.6
## Jump grace: just after walking off a ledge / pressed just before landing.
const PLAYER_COYOTE_SECONDS := 0.1
const PLAYER_JUMP_BUFFER_SECONDS := 0.12
## Dive: hop at launch, minimum lunge time, belly-slide braking, time lying prone.
const PLAYER_DIVE_HOP_VELOCITY := 2.2
const PLAYER_DIVE_SECONDS := 0.3
const PLAYER_DIVE_SLIDE_BRAKING := 28.0
const PLAYER_DIVE_RECOVER_SECONDS := 0.6
## Tackle (F): a short lunge, then the dive's prone recovery. Guards count as
## "in front" inside this cone.
const PLAYER_TACKLE_LUNGE_SPEED := 5.5
const PLAYER_TACKLE_SECONDS := 0.3
const PLAYER_TACKLE_CONE_DEGREES := 120.0
## Interact sensor: a sphere this big, centred this far in front of the body.
const PLAYER_INTERACT_RADIUS := 0.8
const PLAYER_INTERACT_REACH := 0.7
## Letting go of a hold-interaction this soon counts as a press (quick action).
const PLAYER_INTERACT_TAP_SECONDS := 0.3
## Thrown chips land this far in front of the player.
const PLAYER_THROW_DISTANCE := 2.5
## stand_up() steps back from the seat this far.
const PLAYER_STAND_UP_STEP := 0.7
## A new bump on the same guard needs this long without touching it first.
const PLAYER_BUMP_CONTACT_SECONDS := 0.3
## Third-person camera: pivot height, zoom range, look limits and easing.
const PLAYER_CAMERA_HEIGHT := 1.55
const PLAYER_CAMERA_DISTANCE := 4.5
const PLAYER_CAMERA_MIN_DISTANCE := 2.0
const PLAYER_CAMERA_MAX_DISTANCE := 7.5
const PLAYER_CAMERA_ZOOM_STEP := 0.5
const PLAYER_CAMERA_FOV := 70.0
const PLAYER_CAMERA_PITCH_DEFAULT_DEGREES := -20.0
const PLAYER_CAMERA_PITCH_MIN_DEGREES := -70.0
const PLAYER_CAMERA_PITCH_MAX_DEGREES := 25.0
const PLAYER_CAMERA_MOUSE_DEGREES_PER_PIXEL := 0.18
const PLAYER_CAMERA_STICK_DEGREES_PER_SECOND := 180.0
const PLAYER_CAMERA_FOLLOW_SHARPNESS := 20.0
const PLAYER_CAMERA_FOLLOW_SHARPNESS_Y := 8.0
const PLAYER_CAMERA_ZOOM_SHARPNESS := 10.0
const PLAYER_CAMERA_COLLISION_RADIUS := 0.25

# --- casino_map (CasinoBuilder, CasinoMap, Interactable) --------------------
## Graybox casino walls (metres). Doorways are open full height; a lintel
## closes the gap above CASINO_DOOR_HEIGHT.
const CASINO_WALL_HEIGHT := 3.0
const CASINO_WALL_THICKNESS := 0.2
const CASINO_DOOR_HEIGHT := 2.4
const CASINO_FENCE_HEIGHT := 1.6
## Navmesh agent the casino floor is baked for (guards, patrons, forger).
## NAV_CELL_SIZE must match the navigation map's cell size (project default 0.25).
const NAV_AGENT_RADIUS := 0.4
const NAV_AGENT_HEIGHT := 1.8
const NAV_CELL_SIZE := 0.25
## Default reach of an Interactable's sphere.
const INTERACT_RADIUS := 1.0
## Security cameras are mounted this high in the corners of the floor.
const CAMERA_MOUNT_HEIGHT := 2.8
## Patron wander points are spread this far apart along the aisles.
const PATRON_POINT_SPACING := 4.0
## Patrol routes built beyond one per floor guard (spares for special guards).
const EXTRA_PATROL_ROUTES := 2

# --- security_and_crowd (GuardNPC, SecurityCamera, Patron, PatronCrowd) -----
## Guard capsule (feet at the origin), eye height and the point on a player
## a guard or camera must see (line of sight runs eye -> chest).
const GUARD_RADIUS := 0.32
const GUARD_HEIGHT := 1.8
const GUARD_EYE_HEIGHT := 1.6
const SIGHT_CHEST_HEIGHT := 1.2
## How fast a guard turns toward where it walks or looks (higher snaps faster).
const GUARD_TURN_SHARPNESS := 10.0
## A carrying guard this close to the back room point has arrived.
const GUARD_BACK_ROOM_REACH := 1.2
## NavigationAgent3D settings for guards.
const GUARD_PATH_DESIRED_DISTANCE := 0.5
const GUARD_TARGET_DESIRED_DISTANCE := 0.8
const GUARD_AVOIDANCE_RADIUS := 0.45
## A moving destination (a chased player) must shift this far before re-pathing.
const GUARD_REPATH_DISTANCE := 0.35
## A grab not confirmed by the player becoming unavailable this soon counts as freed.
const GUARD_GRAB_CONFIRM_SECONDS := 0.5
## A guard that asked for ID and heard nothing back (the sim refused the
## check) lets the player go after the quiz time plus this long.
const GUARD_ID_RESULT_EXTRA_SECONDS := 1.0
## Radio tips are ignored by a guard already this close to the reported spot
## (it can look for itself).
const GUARD_ALERT_MIN_DISTANCE := 3.0
## Pit boss: stays within this of its post, radios a Suspected+ player at most
## this often (per player), and slowly looks around its tables.
const PIT_BOSS_POST_RADIUS := 3.0
const PIT_BOSS_RADIO_COOLDOWN := 5.0
const PIT_BOSS_LOOK_DEGREES := 60.0
const PIT_BOSS_LOOK_PERIOD := 8.0
## Vision fans are drawn this far above the floor and re-clipped at walls this often.
const VISION_CONE_HEIGHT := 0.04
const VISION_CONE_REFRESH_SECONDS := 0.1
## Security camera: sweep half-angle and full period, downward tilt of the
## housing, turn rate while following someone, spotted cooldown per player.
const CAMERA_SWEEP_DEGREES := 40.0
const CAMERA_SWEEP_SECONDS := 6.0
const CAMERA_TILT_DEGREES := 30.0
const CAMERA_TRACK_DEGREES_PER_SECOND := 60.0
const CAMERA_SPOT_COOLDOWN := 3.0
## Patrons: capsule, walking and rushing speed, pauses between strolls.
const PATRON_RADIUS := 0.3
const PATRON_WALK_SPEED := 1.4
const PATRON_RUSH_SPEED := 4.5
const PATRON_PAUSE_MIN := 2.0
const PATRON_PAUSE_MAX := 6.0
## Patrons re-check their path / stuck state this often (staggered).
const PATRON_REPATH_SECONDS := 1.0
## Share of patrons seated at slot machines (limited by the seats available).
const PATRON_SEATED_SHARE := 0.35
## Thrown chips pull patrons from this far; rushers crowd into this share of
## the rush radius and give up getting there after PATRON_RUSH_MAX_TRAVEL.
const PATRON_RUSH_RANGE := 15.0
const PATRON_RUSH_SPREAD := 0.6
const PATRON_RUSH_MAX_TRAVEL := 5.0

# --- ui (HUD and panels) ----------------------------------------------------
## The HUD and open panels re-read host.snapshot() this often.
const UI_REFRESH_SECONDS := 0.1
## Notification feed: seconds an entry stays, its fade-out, most entries shown.
const UI_NOTIFY_SECONDS := 4.0
const UI_NOTIFY_FADE_SECONDS := 0.6
const UI_NOTIFY_MAX := 6
## Default time a big center banner stays up.
const UI_BANNER_SECONDS := 2.0
## Heat changes at least this big pulse the meter and pop up a delta.
const UI_HEAT_POPUP_MIN := 0.5
const UI_HEAT_PULSE_SCALE := 1.12
const UI_HEAT_PULSE_SECONDS := 0.25
## At Wanted the Heat meter shakes this many pixels.
const UI_HEAT_SHAKE_PIXELS := 4.0
## After a round ends the bet panel locks for this share of the game's round_seconds.
const UI_RESULT_LOCK_SHARE := 0.6
## Lock after a mid-round step (winning high-low guess, blackjack hit).
const UI_HAND_STEP_LOCK_SECONDS := 0.5
## ID quiz: the pass/fail result shows this long before the panel closes.
const UI_QUIZ_RESULT_SECONDS := 1.6
## Cashier preset cash-out amount button.
const UI_CASHIER_PRESET := 100
## Visit banner (thrown out / climbed / curb) auto-closes after this.
const UI_VISIT_BANNER_SECONDS := 5.0
## Debug overlay refresh interval.
const UI_DEBUG_REFRESH_SECONDS := 0.25

# --- table_node (world: TableNode, TableProps) --------------------------------
## play_result with no duration runs this share of the game's round_seconds.
const TABLE_RESULT_SHARE := 0.6
## Shortest result animation, whatever duration is asked for.
const TABLE_RESULT_MIN_SECONDS := 0.2
## Share of a result animation spent spinning / rolling / dealing before the
## win or loss flash; the rest holds the result on screen.
const TABLE_REVEAL_SHARE := 0.75
## Win/loss flash light: peak energy, reach (m) and fade time.
const TABLE_FLASH_ENERGY := 2.5
const TABLE_FLASH_RANGE := 4.0
const TABLE_FLASH_SECONDS := 0.6
## Loud results (big wheel, slot jackpot) strobe brighter, wider and longer.
const TABLE_LOUD_FLASH_ENERGY := 7.0
const TABLE_LOUD_FLASH_RANGE := 9.0
const TABLE_LOUD_FLASH_SECONDS := 1.8
const TABLE_LOUD_FLASH_PULSES := 5
## The result caption stays up this long after it pops, then fades.
const TABLE_POP_HOLD_SECONDS := 1.6
## Chips that burst off the table on a win (loud wins throw more), and how long they fly.
const TABLE_BURST_CHIPS := 8
const TABLE_LOUD_BURST_CHIPS := 24
const TABLE_BURST_SECONDS := 0.8
## Dealer swap: the whole walk-off / walk-in, then how long the new dealer's cold tint lasts.
const TABLE_DEALER_SWAP_SECONDS := 2.4
const TABLE_DEALER_TINT_SECONDS := 4.0
## Reach of a table's interactable sphere.
const TABLE_INTERACT_RADIUS := 1.1
## Whole turns before settling: big wheel, roulette rotor, roulette ball (against the rotor).
const TABLE_WHEEL_TURNS := 3
const TABLE_ROULETTE_TURNS := 2
const TABLE_ROULETTE_BALL_TURNS := 5
## Slot reels flick through this many symbols per second while spinning.
const TABLE_REEL_SYMBOLS_PER_SECOND := 18.0
## Seconds to deal (or flip) one card when show_hand updates a hand.
const TABLE_DEAL_SECONDS := 0.22

# --- casino_director (world: CasinoDirector, main) ----------------------------
## A player seen by guards is reported to the sim (report_seen) at most this often.
const DIRECTOR_REPORT_SECONDS := 0.25
## running_in_view (and "a guard sees you sit down") hold this long after the last sighting.
const DIRECTOR_RUN_FLAG_HOLD_SECONDS := 0.3
## Seconds between the end of a visit (thrown out, climbed) and visit_finished.
const DIRECTOR_VISIT_END_SECONDS := 1.5
## Patrons on the floor per CasinoMap size class.
const DIRECTOR_PATRONS := {&"small": 10, &"medium": 18, &"large": 26}
## At most this many pit bosses (one per table-area post).
const DIRECTOR_MAX_PIT_BOSSES := 2
## A knocked-over tray or chip tower is stood back up after this long.
const DIRECTOR_TRAY_RESET_SECONDS := 20.0
## The celebrate pose after a winning bet.
const DIRECTOR_CELEBRATE_SECONDS := 1.2
## Thrown-chip burst: chips drawn; noise ring: grow time and largest drawn radius.
const DIRECTOR_THROW_CHIPS := 14
const DIRECTOR_NOISE_RING_SECONDS := 0.8
const DIRECTOR_NOISE_RING_MAX_RADIUS := 12.0
## Sitting down turns the player's camera to face the table at this pitch, and
## shifts the view (Camera3D.v_offset, metres) so the table clears the bet panel.
const DIRECTOR_SEATED_CAMERA_PITCH_DEGREES := -38.0
const DIRECTOR_SEATED_CAMERA_V_OFFSET := -1.6

# --- autopilot playtest fixes (broke crew, cashier withdraw) ------------------
## Above Sal's, a crew that can't cover a bet (pockets and bank under the min
## bet) is thrown out after this long on the floor instead of being stuck.
const BROKE_GRACE_SECONDS := 10.0
## The cashier's "take out of the crew bank" button takes at most this many max bets.
const UI_WITHDRAW_MAX_BETS := 10
