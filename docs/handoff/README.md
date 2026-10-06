# Handoff: first-person rebuild in progress

The branch has a working third-person game (single player and LAN co-op) plus the first part of a first-person cartoon rebuild. Work stopped partway through the rebuild.

## Done

- Game rules (`scripts/core/`): Heat, six games, IDs, outfits, posters, ladder, guards, FloorSim. 870 tests pass.
- Third-person world, UI, co-op over ENet (optional GodotSteam), unlocks and local leaderboards.
- Rebuild foundation: toon art kit (`scripts/world/art/`, `assets/shaders/`), first-person player and hands (`scripts/world/fp/`, `player_character.gd`), physical keys, keypads, screens, cards, dice and the `GameMachine` base (`scripts/world/diegetic/`, `scripts/world/machines/`). Reports: `foundation-reports.json`.

## Unfinished (stopped mid-write, untested)

- `scripts/world/machines/slots_machine.gd`, `roulette_machine.gd`, `roulette_board.gd`, `blackjack_machine.gd`, `dice_machine.gd`.
- Not started: big wheel, high-low, Plinko (new game), character restyle, environment restyle (Apex glass dome), physical stations and new HUD, wiring into `casino_director.gd`, retiring the pop-up panels, first-person bots, art polish.
- 3 failing tests in `tests/unit/test_character_model.gd`: `Primitives.material` now returns a toon `ShaderMaterial`, and the old character code reads `StandardMaterial3D` colors. The character restyle fixes this.

## Resuming

- `stage2-workflow.js` is the remaining plan (build, integrate, polish) as agent prompts. Its reference image paths pointed to a cloud scratchpad; put the reference screenshots somewhere local and update `REF`.
- Spec: `docs/ART_DIRECTION.md`. Tests: `./tools/test.sh`. Screenshots: `./tools/screenshot.sh <out> <rung>`.
