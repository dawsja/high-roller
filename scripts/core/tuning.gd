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

const LOSE_ON_PURPOSE_HEAT := -10.0
## One-off cool-down for entering a different game area.
const AREA_CHANGE_HEAT := -6.0
const AREA_CHANGE_COOLDOWN := 20.0
## Per second while off the tables in a bar, buffet or restroom.
const OFF_TABLE_HEAT_PER_SECOND := -2.0
## Per second while seated at a slot machine (blending into the crowd).
const SLOT_BLEND_HEAT_PER_SECOND := -1.0
## Per second anywhere else on the floor while not seated.
const FLOOR_DECAY_PER_SECOND := -0.2
const CHANGE_OUTFIT_HEAT := -15.0

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

## Noise radii (metres) by event.
const NOISE_RADIUS := {
	&"knock_over": 10.0,
	&"big_wheel": 30.0,
	&"slot_jackpot": 25.0,
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
## below to climb into this one. Bet limits and payout_bonus grow going up.
const CASINOS := [
	{"rung": 1, "id": &"apex", "name": "The Apex", "setting": "Rooftop sky casino, glass and gold",
		"guards": 8, "security": [HR.SecurityType.FLOOR_GUARD, HR.SecurityType.CAMERA, HR.SecurityType.PIT_BOSS, HR.SecurityType.UNDERCOVER, HR.SecurityType.HEAD_OF_SECURITY],
		"climb_minutes": 0, "buy_in": 17000, "min_bet": 250, "max_bet": 2500, "payout_bonus": 1.5,
		"floor_color": Color("2b2233"), "wall_color": Color("d9b45a"), "accent_color": Color("f5e6b8")},
	{"rung": 2, "id": &"grand_marquee", "name": "The Grand Marquee", "setting": "Classic strip mega-floor",
		"guards": 6, "security": [HR.SecurityType.FLOOR_GUARD, HR.SecurityType.CAMERA, HR.SecurityType.PIT_BOSS, HR.SecurityType.UNDERCOVER],
		"climb_minutes": 10, "buy_in": 6000, "min_bet": 100, "max_bet": 1000, "payout_bonus": 1.4,
		"floor_color": Color("5a1e2c"), "wall_color": Color("c9a227"), "accent_color": Color("ffd166")},
	{"rung": 3, "id": &"riverboat_queen", "name": "The Riverboat Queen", "setting": "Paddle steamer with narrow decks",
		"guards": 4, "security": [HR.SecurityType.FLOOR_GUARD, HR.SecurityType.CAMERA, HR.SecurityType.PIT_BOSS],
		"climb_minutes": 7, "buy_in": 2000, "min_bet": 50, "max_bet": 500, "payout_bonus": 1.3,
		"floor_color": Color("4a3426"), "wall_color": Color("e8dcc0"), "accent_color": Color("b33a3a")},
	{"rung": 4, "id": &"neon_oasis", "name": "Neon Oasis", "setting": "Off-strip 1970s motel casino",
		"guards": 3, "security": [HR.SecurityType.FLOOR_GUARD, HR.SecurityType.CAMERA, HR.SecurityType.PIT_BOSS],
		"climb_minutes": 5, "buy_in": 500, "min_bet": 25, "max_bet": 250, "payout_bonus": 1.2,
		"floor_color": Color("1f3b4d"), "wall_color": Color("ff6fb5"), "accent_color": Color("3ef0d0")},
	{"rung": 5, "id": &"rusty_spur", "name": "The Rusty Spur", "setting": "Desert truck-stop saloon",
		"guards": 2, "security": [HR.SecurityType.FLOOR_GUARD],
		"climb_minutes": 3, "buy_in": 200, "min_bet": 10, "max_bet": 100, "payout_bonus": 1.1,
		"floor_color": Color("6b4a2e"), "wall_color": Color("c27c3e"), "accent_color": Color("e3c08d")},
	{"rung": 6, "id": &"sals_back_room", "name": "Sal's Back Room", "setting": "Basement card room behind a laundromat",
		"guards": 1, "security": [HR.SecurityType.FLOOR_GUARD],
		"climb_minutes": 2, "buy_in": 0, "min_bet": 5, "max_bet": 50, "payout_bonus": 1.0,
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
