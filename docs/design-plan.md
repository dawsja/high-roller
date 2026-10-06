# High Roller — game design plan

Oct 5, 2026 · @Dawson Dominguez

High Roller is a 1–4 player co-op party game for PC where a crew that wins 85% of its bets tries to stay on the casino floor as long as possible while security closes in. Winning is easy; the game is managing the attention it draws.

## Core loop

A run starts in the top casino and has no game-over screen: getting thrown out drops the crew one casino down, and you gamble your way back up.

[embedded content: core loop · 5 steps, repeating\]

1. Play a table. You choose the bet size; the result is usually a win.
2. Winning adds Heat to you. Bigger bets and longer streaks add more.
3. Security heads for whoever has the most Heat.
4. Teammates pull guards away by winning bigger somewhere else or by causing a scene.
5. You cool off: change tables, lose a hand on purpose, change outfit, swap ID.
6. Cash out at the cashier to bank chips. Chips still in your pockets are lost if you get caught.

Score is chips banked in the top casino plus time survived there.

## Heat

Every player has a Heat meter from 0 to 100, and guards always go for the highest Heat they know about. All numbers here are starting values to tune in playtests.

| Raises Heat | Lowers Heat |
| --- | --- |
| Winning a bet, scaled by bet size | Losing a bet on purpose |
| Each extra win in a streak at one table | Moving to a different game area |
| Sitting at the same table too long | Time off the tables: bar, buffet, restroom |
| Running, table-jumping or bumping guards in their view | Changing outfit |
| Matching a wanted poster | Blending into the crowd at a slot machine |

| Level | Heat | What security does |
| --- | --- | --- |
| Unnoticed | 0–24 | Nothing |
| Watched | 25–49 | Cameras follow you. The casino swaps the dealer and your win rate at that table falls to 50% until you leave. |
| Suspected | 50–79 | A guard walks over and asks for ID |
| Wanted | 80–100 | Guards chase you and a poster of your current look goes up |

The cooled table is what keeps players moving around the floor instead of camping one seat.

## Security

Five security types are added as you climb the ladder, so the bottom casinos stay simple and the top one has everything.

| Type | Behavior | First appears |
| --- | --- | --- |
| Floor guard | Patrols a route, checks IDs, chases, carries you out | Sal's Back Room |
| Camera | Sweeping cone. Adds Heat and records your outfit for posters | Neon Oasis |
| Pit boss | Stands over a table area. Heat builds faster in view; radios the nearest guard | Neon Oasis |
| Undercover | Dressed as a patron with an earpiece. Grabs you with no warning walk | The Grand Marquee |
| Head of security | One per map. Fast, and remembers you through one outfit change | The Apex |

[embedded content: guard behavior · 6 states\]

A guard returns to patrol when an ID passes, a search times out, or the escort ends. A grab leads to the back room unless a teammate frees you.

Guards see with a vision cone plus a line-of-sight check, and hear noise events within a radius. The host runs all guard logic.

## Crew play

The crew lasts longest by passing Heat around, so no one player stays at the top of security's list.

| Distraction | Effect | Cost |
| --- | --- | --- |
| Win big elsewhere | Guards retarget once your Heat passes your friend's | Your own Heat |
| Throw chips | Patrons rush in and block guards for a few seconds | Chips |
| Knock over a drink tray or chip tower | Nearest guard investigates the noise | Small Heat |
| Bump or body-block a guard | Guard ragdolls and the chase breaks briefly | Large Heat |
| Trip a slot jackpot alarm | Pulls every guard in earshot | Long cooldown |
| Pull the fire alarm | Clears guards off the floor and closes tables for a short time | Once per casino visit |

Getting caught:

1. A guard grabs you and carries you toward the back room. Mashing a button slows them down.
2. A teammate can free you by tackling the guard before the door. The tackler goes straight to Wanted.
3. If you reach the back room, you lose the chips you carry, your current ID is burned, and the crew takes a strike. You rejoin after a short timeout.
4. Three strikes, or the whole crew detained at once, and everyone is thrown out to the next casino down.

The crew drops together so everyone stays on one map.

## Identity

Security tracks two things about you: what you look like and what name you play under. Outfits reset the first, fake IDs reset the second.

**Outfits**

- Five slots: hat, glasses, top, bottom, accessory.
- Guards and cameras record your look when you reach Suspected. A match on three of the five slots counts as recognized.
- Change in restrooms from your stash, buy pieces at the gift shop, or steal from laundry carts and staff lockers.
- A staff uniform lets you walk past guards and into back areas, but staff cannot sit at tables.

**Wanted posters**

- Going Wanted prints a poster of your current outfit on boards at the entrance, the cashier and the security desk.
- A guard who sees you matching a poster skips the walk-over and goes straight to an ID check.
- Tear a poster down (slow and noisy) or draw on it to knock out one matching slot.
- Posters stay up between visits. Come back to a casino that threw you out and your old look is still on the wall.

**Fake IDs**

- You always play under an ID. Guards and the cashier ask for it.
- Each ID has a winnings cap. Bank more than the cap under one name and the name is flagged, so its next check fails.
- A burned ID fails every check. Buy new ones from the forger, who moves between the parking garage, restroom and loading dock.
- Three grades: cheap (low cap, sometimes spotted on sight), solid, and flawless (high cap).
- The ID check is a quiz. The guard asks one detail from the card, such as name, birthday or home state, and you pick from three answers on a short timer.
- IDs get silly generated names, so swapping often means more to remember.

## Casino ladder

Six casinos form a ladder: every thrown-out drops the crew one rung, and each lower rung is quicker to climb out of. Names and themes are placeholders.

| Rung | Casino | Setting | Security | Target time to climb out |
| --- | --- | --- | --- | --- |
| 1 | The Apex | Rooftop sky casino, glass and gold | 8 guards, every security type | None. This is the scoring floor |
| 2 | The Grand Marquee | Classic strip mega-floor | 6 guards, cameras, pit bosses, undercover | 10 min |
| 3 | The Riverboat Queen | Paddle steamer with narrow decks; you can jump overboard and climb back on | 4 guards, cameras, pit bosses | 7 min |
| 4 | Neon Oasis | Off-strip 1970s motel casino | 3 guards, first cameras and pit bosses | 5 min |
| 5 | The Rusty Spur | Desert truck-stop saloon | 2 guards | 3 min |
| 6 | Sal's Back Room | Basement card room behind a laundromat | 1 sleepy guard | 2 min |

- To climb, bank the buy-in for the casino above, then get the whole crew to the exit. Buy-ins are tuned to hit the target times.
- Bet limits and payouts grow with each rung, so the top floor is where real scores happen.
- Sal's is the floor. Getting caught there is a short timeout on the curb, not a drop.
- Stretch rule: bank double the buy-in to skip a rung.

## Games

Every game wins 85% of the time by default, so games differ in payout and Heat rather than odds. The host rolls the result first, then the table animates to match it.

| Game | Round | Payout | Heat per win | Twist |
| --- | --- | --- | --- | --- |
| Slots | 3 s | Low | Low | Sitting at a machine hides you in the crowd. A rare jackpot rings bells and pulls guards |
| High-low cards | 4 s | Low, doubles each streak | Builds fast | Cash out or double |
| Big wheel | 5 s | High | High | Loud. Everyone in the room sees the result |
| Dice | 6 s | Medium | Medium | The whole crew can bet on one roll and split the Heat |
| Roulette | 8 s | Medium on a color, very high on a number | Matches the payout | You pick your own risk |
| Blackjack | 10 s | Medium | Medium | Hit or stand only |

- No round runs longer than 10 seconds. The fun is on the floor, not in a card menu.
- The two bottom casinos reskin the set: bingo, scratch cards, a coin pusher.
- Later additions: plinko, horse-race screens, a poker showdown against patrons.

## Scoring and progression

Chips only count once they are banked, which makes every trip to the cashier a risk.

- Pocket chips are lost when you are caught. Banked chips are safe.
- The cashier asks for ID, and a large cash-out adds Heat.
- Hand chips to a teammate so the hottest player is never the one carrying.
- Run score is chips banked at The Apex plus minutes survived there, posted to Steam leaderboards by crew size.
- Lifetime banked chips unlock outfit pieces, emotes and ID name packs. Unlocks are cosmetic and nothing is sold for real money.

## Tech

One player hosts and everyone connects through Steam, so there are no servers to run or pay for.

| Area | Choice | Why |
| --- | --- | --- |
| Engine | [Godot 4.7](https://godotengine.org/download/archive/), GDScript | Current stable line; 4.8 is still in dev snapshots |
| Networking | Godot's RPCs, MultiplayerSpawner and MultiplayerSynchronizer over the [GodotSteam MultiplayerPeer](https://godotsteam.com/howto/multiplayer_peer/) | Steam lobbies, friend invites and relay with the standard Godot multiplayer nodes |
| Authority | Host owns game results, Heat, guards and posters. Each client owns its own movement | Simple, and fine for friends-only co-op |
| Local testing | Swap in Godot's ENet peer | Run four clients on one machine without Steam |
| Player | CharacterBody3D, third-person camera, run, jump, dive, tackle, ragdoll on hit | Party-game feel |
| Guards and patrons | State machine plus NavigationAgent3D on a baked navmesh. Patrons update at a low rate | Dozens of characters on the floor cheaply |
| Steam | Lobbies, invites, achievements, leaderboards, cloud save for unlocks |  |

Before locking the engine version, confirm the GodotSteam release you use is built for it.

**Blender pipeline**

- Flat-shaded low poly with one shared palette texture, so the whole casino draws with one material.
- A modular kit on a 2 m grid: floors, walls, pillars, doors, stairs, tables, machines. Six casinos are one kit with new palettes and a few hero props each.
- One character rig for players, guards and patrons. Outfit pieces are separate meshes skinned to that skeleton and toggled per slot.
- Export glTF (.glb). Name collision meshes with the `-col` suffix so Godot builds colliders on import.
- First animation set: idle, walk, run, jump, dive, sit, play, celebrate, tackle, carried.

## Build plan

Five phases, each ending at a gate that must pass before the next one starts. There are no dates yet because they depend on team size and weekly hours.

[embedded content: build roadmap · 5 phases, 5 gates\]

If the phase 1 prototype is not fun with one player and one guard, fix that before writing any network code.

## Risks and open decisions

Networking and scope are the two things most likely to sink the project, so the plan front-loads the first and cuts the second.

| Risk | Response |
| --- | --- |
| Multiplayer bolted on late | Build the Steam multiplayer slice second, before any content |
| Six maps and six games is a lot | Enter Early Access with The Apex and the bottom two rungs. Add the middle three after |
| An 85% win rate can feel flat | Put the tension in Heat and payouts. Never fix it by making mini-games longer |
| Age rating | [PEGI rates new games with simulated gambling 18](https://www.gamedeveloper.com/business/gambling-in-your-game-will-now-automatically-land-it-a-pegi-18-rating). Plan for an adult rating in Europe, and never sell chips or random items for real money |
| Party splits up | The crew shares strikes and drops together |

Open decisions:

- [ ] Crew drops together (assumed here), or each caught player drops alone?
- [ ] Climb one rung at a time (assumed), or straight back to the top casino?
- [ ] Crew size: 4 (assumed) or up to 6?
- [ ] Team size and weekly hours, to put dates on the build plan
- [ ] Final casino names and themes

## Sources

- [Godot download archive](https://godotengine.org/download/archive/): 4.7.2 stable released 18 August 2026; 4.8 at dev7
- [GodotSteam: How-To Multiplayer Peer](https://godotsteam.com/howto/multiplayer_peer/): works with Godot's RPCs, MultiplayerSynchronizer and MultiplayerSpawner
- [Game Developer: PEGI 18 for simulated gambling](https://www.gamedeveloper.com/business/gambling-in-your-game-will-now-automatically-land-it-a-pegi-18-rating): applies to new games since 2020
- [PEGI: What do the labels mean](https://pegi.info/what-do-the-labels-mean): read from search results only; the page blocks automated access
