class_name HR
extends RefCounted
## Shared enums. Values are stable: they go over the network and into saves.

enum HeatLevel { UNNOTICED, WATCHED, SUSPECTED, WANTED }

enum GameType { SLOTS, HIGH_LOW, BIG_WHEEL, DICE, ROULETTE, BLACKJACK }

## How much Heat a win at a game produces (design doc "Heat per win").
enum HeatClass { LOW, MEDIUM, HIGH, VERY_HIGH }

## The six guard states from the design doc, plus STUNNED for a bumped/tackled guard.
enum GuardState { PATROL, INVESTIGATE, CHECK_ID, CHASE, SEARCH, CARRY, STUNNED }

enum SecurityType { FLOOR_GUARD, CAMERA, PIT_BOSS, UNDERCOVER, HEAD_OF_SECURITY }

enum OutfitSlot { HAT, GLASSES, TOP, BOTTOM, ACCESSORY }

enum IdGrade { CHEAP, SOLID, FLAWLESS }

## What kind of place a player is standing in. Each zone also has an area_id
## (StringName) so "moving to a different game area" can be detected.
enum ZoneType { FLOOR, TABLES, SLOTS, BAR, BUFFET, RESTROOM, CASHIER, GIFT_SHOP, BACK_ROOM, EXIT, STAFF_ONLY, ENTRANCE, FORGER }

enum PlayerStatus { FREE, SEATED, ID_CHECK, CARRIED, DETAINED, ON_CURB }

## Distractions from the design doc "Crew play" table.
enum Distraction { WIN_BIG, THROW_CHIPS, KNOCK_OVER, BUMP_GUARD, SLOT_ALARM, FIRE_ALARM }

const OUTFIT_SLOT_COUNT := 5
