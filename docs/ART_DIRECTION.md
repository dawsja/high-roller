# Art direction and first-person play

High Roller is played in **first person**. You walk up to a game and play it with your hands, on the machine itself: you press its keypad keys, pull its lever, throw its dice and click chips onto its felt. There are no pop-up game menus. 2D screens are kept for the title, lobby, pause, banners and a small HUD only.

## Look

Chunky, toy-like, saturated cartoon. Everything reads at a glance from across the floor.

- **Shapes.** Rounded everything: bevelled boxes, pills, blobs, fat cylinders. No sharp thin parts. Proportions are exaggerated: big buttons, big screens, big signs.
- **Shading.** Toon shading with 2–3 light bands, a soft rim light, and a dark purple outline (inverted hull) on characters, machines and props. Walls and floors get no outline.
- **Palette.** Night-club casino: deep purples and indigos for walls and ceilings (`#2a1640`, `#3b1d5e`, `#1c1033`); hot neon accents (magenta `#ff3fd2`, cyan `#3ef0ff`, lime `#b6ff3b`, sunflower `#ffd23f`, orange `#ff8a3d`); warm felt greens and casino reds on tables. Each casino keeps its own palette from `Tuning.CASINOS`, pushed toward this saturation.
- **Neon.** Emissive strips along edges, geometric wall art (triangles, lightning bolts, squares, circles, dice, cocktail glasses), and neon signs over each game area. World glow (bloom) is on, so neon actually glows.
- **Floors and walls.** Loud patterned carpet (circles, swirls, eye-like dots) and patterned wall panels, made with procedural shaders. Ceilings are back: patterned or paneled, with neon light strips.
- **Lighting.** Bright and readable. High ambient light in the casino palette, a few coloured omni lights per area, no pitch-black corners.
- **Labels.** Big floating white game names over each machine (`SLOTS`, `ROULETTE`, ...), bold font with a dark outline, billboarded and fading with distance. Fonts: Lilita One for display, Fredoka for body text (`assets/fonts`, OFL).
- **Characters.** Original cartoon creatures, not humans. Bean, pear or blob bodies with huge round googly eyes (white with big black pupils, eyelids that blink), a small nose or beak, stubby arms with round mitten hands and short legs. Several body species and skin colours. Outfit pieces sit on top (hats, glasses, tops, bottoms, accessories). Guards are bulky bouncers in navy with caps and shades. Dealers wear vests and bow ties. Pit bosses have mustaches, and the head of security is huge.
- **Hands.** In first person you see two big soft mitten hands at the bottom of the screen. They bob while you walk, reach and press when you click, hold dice, flip your ID card up and throw chips.

## Interaction

- A small dot crosshair sits at screen centre. Looking at anything usable within reach (~2.6 m) gives it a bright glowing outline and a small hint label (`[LMB] PLAY`, `[Hold E] Tear down`).
- **Left mouse** presses whatever you look at. **E** uses or holds things (doors, posters, trays). Keys 1–3 answer the ID quiz. **Tab** raises your fake ID card into view (scroll to swap cards).
- Every game is a physical machine with a **bet console**: often a panel on its own stand beside the table. It has a numeric keypad (0–9, `C`, `000`), a screen showing the bet big with `Min` and `Max` above it, and a column of orange quick keys (`MIN`, `¼`, `½`, `ALL`, plus `MAX`). A big separate green `PLAY` / `SPIN` / `ROLL` / `DEAL` button sits on the table rail, and a `THROW` key loses on purpose. Some machines have more fat colored keys on the rail: yellow `STAND`, red `HIT` and green `PLAY` for blackjack; `CASH OUT`, `HIGHER` / `LOWER`.
- A hovered key gets a thick yellow outline, a small pointing-hand cursor and a hint label under it (`BUTTON  [LMB] INTERACT`).
- Card totals float above the cards as big outlined numbers (e.g. `17` for you, `22` for the dealer). A short instruction plaque is printed on the felt (`Beat the dealer without busting 21`, `Roll the dice and beat the odds`).
- Standing in a machine's play spot sits you at it in the simulation (Heat, camping, dealer swap). Walking away stands you up.
- Results play out physically on every peer: reels spin and stop, the wheel and ball spin, dice tumble and settle, cards fly from the shoe and flip. Monitors on stands show the odds, the result and the payout.
- Other stations are physical too: the cashier cage console, the restroom mirror with an outfit rack, gift-shop shelves with price tags, the forger opening his coat full of IDs, poster boards, drink trays, the fire alarm and the exit door with a buy-in monitor. A guard's ID check is a speech bubble with three answer cards floating in front of you.

## Per-casino notes

- **The Apex** is a rooftop sky casino: a huge glass dome ceiling with a gold lattice of panes showing a bright blue sky, white and gold walls, chandeliers, palm plants and a starry blue carpet with pink cards.
- **Neon Oasis** and **the Grand Marquee** are the purple neon club look (ref1 and ref4).
- **Sal's** is a cramped basement with exposed pipes, a laundromat door and one sleepy guard, but it keeps the same cartoon shading and loud colors.

## Plinko

Plinko joins the six games. It is a tall arched cabinet with a peg board (bright green pill pegs on a gold field) and a row of multiplier buckets along the bottom (`24x 6x 2.8x 1.2x 0.5x 0.2x 0.2x 0.5x 1.2x 2.8x 6x 24x`). You press PLAY and a chip drops, bouncing peg to peg along the path the host rolled, into its bucket. The bet console sits on the cabinet's front.

## References

The user's reference screenshots are in the session scratchpad `ref/` folder (`ref1`–`ref8`): keypad console, character and roulette, roulette board, slots, dice in hands, blackjack keys, bet console on a stand, and plinko under the Apex glass dome. Match their vibe with original designs.

## HUD (2D, minimal)

- Top right: pocket chips, large and green (`$1.5K`), with the climb target under it in red (`/ $6K`) or the score at the top rung.
- Top centre: Heat meter, a chunky segmented pill coloured by level, with the time at the top under it.
- Top left: casino name, strikes and teammates.
- Bottom right: key hints. Notifications are toasts on the right side.
- Status overlays: carried (`MASH SPACE`), detained countdown, curb.
