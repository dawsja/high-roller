# High Roller

A co-op casino party game for 1 to 4 players. The crew wins 85% of its bets.
The game is about staying on the casino floor while security closes in.
Winning raises your Heat. Guards go after whoever has the most Heat. You cool
off by changing tables, changing outfits, swapping fake IDs, or losing a hand
on purpose. You bank chips at the cashier before a guard carries you out.

This repository is the **phase 1 prototype** (one player against the full
security roster, on graybox maps built from primitives) plus the **phase 2
co-op slice**: a crew of 1 to 4, host-authoritative, over LAN / localhost
(ENet) or friends-only Steam lobbies when GodotSteam is installed. The full
design is in [`docs/design-plan.md`](docs/design-plan.md). The code map and
module contracts are in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
(co-op: "Networking").

## Running it

You need **Godot 4.7** (4.7.2 stable or later in the 4.7 line).

- Editor: open the project folder in Godot and press **F5**. The main scene is `scenes/main.tscn`.
- Command line: `godot --path .`
- Skip the title screen, for testing: `godot --path . -- --autostart --rung=6 --practice`
  - `--rung=N`: start casino, 1 (The Apex, the top) to 6 (Sal's Back Room, the bottom)
  - `--practice`: one floor guard and no other security
  - `--seed=N`: a fixed run seed (otherwise random)
  - `--autostart`: start straight away, without the title screen
  - `--autopilot`: a bot plays the game and prints its timeline (implies `--autostart`)
  - `--autopilot-seconds=N`: with the bot, quit after N simulated seconds and print its summary
  - `--speed=N`: run the game N times faster (the physics step stays 1/60 s)
- Watch the bot play a practice run, 8x fast, headless:
  `godot --headless --path . -- --practice --rung=6 --autopilot-seconds=300 --speed=8`
- Co-op from the command line (see "Play co-op"):
  - `--host[=port]`: host a crew (default port 24565); with `--autostart` the
    run starts once `--players=N` are in the crew
  - `--join=address[:port]`: join a host
  - `--name=NAME`: your name in the crew
  - `--net-log`: print one `NET ...` line per network event
  - `--net-bot`: the scripted co-op test bot plays (`tools/net_bot.gd`)
  - `--quit-after-seconds=N`: quit after N real seconds

The title screen has two ways to start. **Start run at The Apex** starts a
normal run at the top casino. **Practice at Sal's Back Room** starts at the
bottom casino with one sleepy guard. The co-op box under them hosts or joins
a crew.

## Play co-op

One player hosts and runs the casino; everyone else joins. The host decides
every result, the Heat, the guards and the posters; each player moves their
own character.

1. **Host:** type your name, then **Host co-op** (port 24565 by default; open
   it on your router or firewall for players outside your LAN). The lobby
   lists the crew as they join.
2. **Join:** type your name, the host's address and port, then **Join co-op**.
   Joining works in the lobby only, not once the crew is in a casino.
3. With GodotSteam installed, **Steam: host lobby / invite friends** opens a
   friends-only lobby; **Invite Steam friends** in the lobby opens the Steam
   overlay, and friends join by accepting the invite.
4. The host picks **Start the run at The Apex** or **Practice at Sal's**.

In the casino the HUD lists your crew (name, Heat level, what they're up to)
and nameplates float over your teammates. Crew play:

- **Tackle (F)** the guard carrying a teammate: they're free, you're Wanted.
- **Hand chips (H)** to the nearest teammate (half your pocket).
- Sit at the **same dice table**: everyone's bets go on one roll (3 s to get in).
- **Climb together:** the whole crew (except anyone detained) has to stand on
  the EXIT pad. Walking out of The Apex ends the run for everyone.
- The crew shares the bank and the strikes, and a crew that is all held at
  once is thrown out together.

If the host leaves, everyone goes back to the title. If a teammate leaves,
their body vanishes and the crew carries on (their pocket chips go with them).
Pausing doesn't stop a co-op game.

Four players on one machine (for testing):

```
godot --path . -- --host --name=Ann --autostart --players=4 --practice --rung=6
godot --path . -- --join=127.0.0.1 --name=Bob     # three times
```

## Controls

| Action | Keyboard / mouse | Gamepad |
| --- | --- | --- |
| Move | WASD or arrow keys | Left stick |
| Look / zoom | Mouse / wheel | Right stick |
| Run | Shift | LB or left-stick click |
| Jump (also: struggle while carried) | Space | A |
| Dive | Ctrl | B |
| Interact (hold for hold actions) | E | X |
| Tackle | F | RB |
| Throw chips | G | Y |
| Knock over a tray | Q | RT |
| Hand chips to the nearest teammate (co-op) | H | D-pad down |
| Pause | Esc | Start |
| Debug overlay | F3 | Back |
| ID quiz answers | 1 / 2 / 3 | D-pad left / up / right |

At a table: **Space** places the bet, deals, or cashes out a high-low pot.
**1 / 2 / 3** pick a choice (red, black or number; higher or lower; hit or
stand). **+ / −** or the arrow keys change the bet. **Esc** leaves the table.
The mouse is free while a panel is open. Click the 3D view to capture the mouse again.

## Playing

1. **Sit at a table** (E) and bet. You win most of the time, but every win adds Heat.
2. **Watch your Heat.** At **Watched** (25), the cameras follow you and the
   dealer gets swapped, so your odds at that table drop to 50%. At **Suspected**
   (50), a guard walks over and asks for ID. Answer the quiz from the card on
   your HUD (1/2/3). At **Wanted** (80), guards chase and grab you, and a
   wanted poster of your outfit goes up.
3. **Cool off.** Move to another game area, sit at the slots, spend time in
   the bar, buffet or restroom, or lose a bet on purpose ("Throw it"). You can
   also change outfits in the restroom, buy pieces at the gift shop, or steal
   them from laundry carts and staff lockers. The forger (trench coat; the
   HUD feed says where he moved) sells fresh IDs.
4. **Distractions.** Throwing chips (G) draws patrons, who block guards. Knocking
   over a tray (Q) makes a guard investigate the noise. Running into a guard
   or tackling one (F) stuns it, and frees a carried teammate. The jackpot
   alarm post draws every guard in earshot. The fire alarm clears the floor
   and closes the tables (once per visit). Posters can be drawn on (tap E) or
   torn down (hold E).
5. **Bank chips** at the cashier. Chips in your pocket are lost when a guard
   carries you to the back room. Banked chips are safe: the cashier hands
   them back out of the crew bank when you need a stake (except what you
   banked at The Apex, which is your score). A crew that is out of chips with
   nothing in the bank is walked out, down to a casino it can afford. A trip to the back room is also a strike.
   Three strikes and the crew is thrown out to the next casino down. At Sal's
   it's a short timeout on the curb instead.
6. **Climb.** Bank the buy-in, then walk to the EXIT pad outside to move up a
   casino. Banking double skips a rung. At The Apex, everything you bank and
   every minute you survive count toward your score. Walking out of The Apex
   ends the run and shows the score.

## What phase 1 implements

Implemented, against the design doc:

- The whole simulation: Heat and its levels, six table games (85% default
  win rate, cooled tables at 50%), outfits, wanted posters that stay up
  between visits, fake IDs with caps and the ID quiz, the forger, the
  cashier, the six-casino ladder with buy-ins, strikes and throw-outs, and
  scoring at the top. All of it runs host-authoritatively in `scripts/core/`
  (`FloorSim`, `RunState`) behind `SimHost`.
- Every security type: floor guards (patrol, investigate, ID check, chase,
  carry, search), cameras, pit bosses (watch and radio), undercover guards, and
  the head of security. Guards use vision cones with line of sight, hear
  noise events, and walk a baked navmesh.
- Patrons who wander, sit at slot machines and rush to thrown chips.
- Every distraction in the "Crew play" table, getting caught (struggle,
  tackle-to-free, back room, rejoin), the curb at Sal's, and climbing.
- A graybox casino for each rung, in three size classes and each casino's
  palette, with game areas, a cashier, restrooms, a gift shop, a bar, a
  buffet, a staff corridor, a back room, a parking garage, a loading dock and
  an exit pad.
- The HUD, the table panel, the ID quiz, the cashier, the wardrobe (restroom,
  gift shop, steal), the forger panel, the title, pause, visit banners and a
  debug overlay (F3).

Phase 2 co-op slice (see "Play co-op" and `docs/ARCHITECTURE.md`, "Networking"):

- `NetSession` with an ENet backend and a dynamic GodotSteam backend (friends-only
  lobbies, invites), a roster, a lobby, and the crew HUD and nameplates.
- `SimHost` as the RPC boundary: validated client requests and replies,
  batched events and snapshots, MultiplayerSynchronizers for players, guards,
  cameras and patrons with a ready handshake, host-to-owner placements, and
  the crew mechanics (tackle a carrier, hand chips, shared dice rolls,
  crew-wide climb).

Not built yet (later phases in the design doc):

- Joining a crew that is already in a casino, and rejoining after a drop.
- Blender art, rigged animation and ragdolls. Everything is primitives with
  procedural poses.
- Audio, Steam achievements, leaderboards and unlocks.
- Casino-specific twists, such as the Riverboat Queen's "jump overboard",
  and the plinko, horse-race and poker additions.

## Tests

```
./tools/test.sh            # the whole suite
./tools/test.sh director   # only test files whose path contains "director"
```

The script copies the project to a temp directory, imports it, and runs
`tests/run_tests.gd` headless. That runs every `test_*` method in
`tests/unit/test_*.gd` and `tests/integration/test_*.gd`. The run fails on any
failed assert, and on any `SCRIPT ERROR`, parse error or engine `ERROR:` line
in the output.

- `tests/unit/`: one file per module, covering the core logic and each world
  node on its own.
- `tests/integration/test_sim_scenarios.gd`: whole-visit scenarios run on
  the simulation alone.
- `tests/integration/test_casino_director.gd`: builds real visits (Sal's in
  practice mode, The Apex) and checks security and table counts. It also runs
  the sit-and-bet path through the table interactable and the bet panel, an ID
  check, a guard drawn by a knocked-over tray, and a full grab, carry and back
  room sequence. That sequence goes on through three strikes to a throw-out,
  the next visit one rung down, and a climb back up, where the old wanted
  poster is still on the wall.
- `tests/integration/test_autopilot.gd`: the `Autopilot` bot (`tools/autopilot.gd`)
  plays the real game at 8x speed through input actions and the UI panels: a
  practice run at Sal's (bets, dealer swaps, an ID check or chase, banking, a
  climb, and play in the next casino) and an Apex run with every security
  type. Its watchdogs must stay quiet.
- `tests/integration/test_net_two_process.gd`: co-op over real sockets. It
  runs `tools/net_test.sh 1`: a headless host and client on localhost play
  the scripted `NetBot` and the script checks their `--net-log` lines (see
  `docs/ARCHITECTURE.md`, "Testing co-op locally"). It skips where no UDP
  socket can be opened. `./tools/net_test.sh 3` runs a crew of four.
- `tests/unit/test_net_*.gd`, `tests/integration/test_net_director.gd`: co-op
  without sockets (request validation, the wire format, puppets, placements).
- `tests/integration/test_smoke.gd`: runs `scenes/main.tscn` with the title
  screen, autostart and 600 physics frames of walking around. It also covers
  pause and restart, a throw-out followed by the next visit, and a climb
  through the exit.

## Screenshots

```
./tools/screenshot.sh <out_dir> [rung] [--practice] [--seed=N]
```

This needs `xvfb-run`. It renders one visit with the OpenGL renderer on a
virtual 1600x900 display and saves these PNGs into `<out_dir>`:

- `00_title`: the title screen
- `01_player`: the third-person view
- `02_overhead`: an overhead of the whole map
- `03_table`: a table mid-result with the bet panel open
- `04_hud`: a HUD close-up

The driver script is `tools/screenshot.gd`. With `--coop` it first starts a
headless host and then shoots a client's view: `05_coop_view` (a teammate's
nameplate), `06_coop_hud` (the crew panel) and `07_lobby`.

## Project layout

```
project.godot           main scene: scenes/main.tscn (input actions are registered in code)
scenes/main.tscn        the only hand-written scene: a Node with scripts/main.gd
scripts/main.gd         title / lobby -> run -> visits, pause menu, UI layers, command-line options
scripts/net/            co-op: NetSession, ENet and Steam backends, NetSync, NetLog
scripts/core/           pure simulation (RefCounted, no scene tree): FloorSim, RunState, HeatMeter,
                        GuardBrain, table games, outfits, posters, IDs, Tuning (all numbers), HR (enums)
scripts/world/          Godot nodes: SimHost (the sim's host and future RPC boundary), CasinoDirector
                        (one per visit: builds and wires everything), CasinoBuilder/CasinoMap,
                        PlayerCharacter + CameraRig, GuardNPC, SecurityCamera, PatronCrowd,
                        TableNode, CharacterModel, Interactable, CasinoZone, PosterBoardNode
scripts/ui/             HUD and panels, all built in code (UiTheme holds the shared look)
tests/                  test runner, TestCase, unit/ and integration/ tests
tools/test.sh           headless test runner
tools/screenshot.sh     review screenshots under xvfb
tools/autopilot.gd      the Autopilot bot (tests and --autopilot)
tools/net_test.sh       co-op over localhost sockets: a host and 1-3 clients, checked from their logs
tools/net_bot.gd        the scripted co-op bot (--net-bot)
docs/                   design plan and architecture
```

All tunable numbers live in `scripts/core/tuning.gd`. World and UI nodes never
change chips, Heat, IDs or outfits themselves. They call `SimHost.request_*`
and react to `SimHost.sim_event` (see `docs/ARCHITECTURE.md`, "World layer").
