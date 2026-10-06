class_name FpTuning
extends RefCounted
## First-person tunables: the head camera, look, reach and the hands. World
## presentation only (no game rules); kept beside the first-person code.

# --- Head and look ------------------------------------------------------------
## Eye height standing (players are chunky cartoon creatures).
const EYE_HEIGHT := 1.55
## Eye height seated at a table (thighs level, see CharacterModel.SIT_HIP_Y).
const SEATED_EYE_HEIGHT := 1.2
const FOV := 78.0
## Extra field of view while running flat out.
const RUN_FOV_BONUS := 5.0
const FOV_SHARPNESS := 6.0
const NEAR := 0.03
## Look limits up and down (degrees from level).
const PITCH_LIMIT_DEGREES := 85.0
## Default mouse sensitivity (CameraRig.mouse_sensitivity).
const MOUSE_DEGREES_PER_PIXEL := 0.11
const STICK_DEGREES_PER_SECOND := 200.0
## How fast the head eases to a new eye height / offset (1/s).
const EYE_SHARPNESS := 14.0
const EFFECT_SHARPNESS := 11.0

# --- Head bob and landing -----------------------------------------------------
## Step length walking and running (m); one footstep per half bob cycle.
const STEP_WALK := 0.85
const STEP_RUN := 1.35
const BOB_HEIGHT := 0.04
const BOB_SIDE := 0.022
const BOB_ROLL_DEGREES := 0.7
const BOB_SHARPNESS := 9.0
## Landing dip: metres of dip per m/s of landing speed, capped.
const LAND_DIP_PER_SPEED := 0.018
const LAND_DIP_MAX := 0.22
const LAND_SPRING := 90.0
const LAND_DAMPING := 13.0

# --- Actions ------------------------------------------------------------------
## Dive: the eye drops this low and lunges forward, lying prone after.
const DIVE_EYE := 0.55
const PRONE_EYE := 0.4
const DIVE_LUNGE := 0.35
const DIVE_PITCH_DEGREES := -14.0
const DIVE_ROLL_DEGREES := 6.0
## Tackle shove: a small forward lunge and dip.
const TACKLE_LUNGE := 0.25
const TACKLE_DIP := 0.12
## Knocked over: the eye falls to the floor looking up.
const TUMBLE_EYE := 0.35
const TUMBLE_PITCH_DEGREES := 55.0
const TUMBLE_ROLL_DEGREES := 14.0
## Carried over a guard's shoulder: the eye sits this far up and behind the
## carry point, looking back and down, with a wobble.
const CARRIED_UP := 0.2
const CARRIED_BACK := 0.38
const CARRIED_PITCH_DEGREES := -42.0
const CARRIED_LOOK_LIMIT_DEGREES := 100.0
const CARRIED_WOBBLE_DEGREES := 7.0

# --- Pressing -------------------------------------------------------------------
## Reach of the look ray (m) against physics layer 5.
const REACH := 2.6
## The ray skips this many legacy / disabled hits looking for a pressable.
const RAY_MAX_HOPS := 4
## Physics layer 5 (interactable / pressable) as a bit value.
const PRESS_MASK := 16
## The hands pull back when a wall is closer than this to the eye.
const HANDS_CLEARANCE := 0.62

# --- Rendering ------------------------------------------------------------------
## VisualInstance3D layer (bit value) of the local player's own body: its own
## camera leaves it out, every other camera sees it.
const SELF_BODY_LAYER := 1 << 18
## VisualInstance3D layer of the first-person hands and the raised ID card:
## only meant for the local camera. Any in-world camera (a monitor feed)
## should leave it out of its cull_mask.
const VIEW_LAYER := 1 << 17
