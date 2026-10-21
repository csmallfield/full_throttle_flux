@tool
extends Resource
class_name TrackJump

## A designed jump (v31): kicker ramp, a gap with no road, a landing ramp.
## Distances are metres along the path the jump is on (the MainSpline, or a
## TrackBranch's Path3D). Owned by a TrackGraph.
##
##   kicker_start .. lip        kicker ramp (road)
##   lip .. landing             the gap (no road, no collision below)
##   landing .. landing_end     landing ramp (road), back to level
##
## What it changes:
##   * Respawns: no respawn point from `respawn_runup` metres before the kicker
##     to landing_end, so a ship that falls short comes back far enough before
##     the jump to get up to speed for it, on the same path.
##   * Ship physics, only for a flight that TOOK OFF from this jump (see
##     ShipController, "Jump flight"): air drag and the landing spring. A ship
##     launched off a crest anywhere else keeps the profile's normal air
##     physics, and tracks without jumps are untouched.

@export var jump_name: String = "Jump"

## -1 = on the MainSpline, otherwise an index into TrackGraph.branches.
@export var branch: int = -1

@export_group("Extent (path metres)")
@export var kicker_start: float = 0.0
@export var lip: float = 0.0
@export var landing: float = 0.0
@export var landing_end: float = 0.0

## No respawn points this far before kicker_start (run-up from standstill).
@export var respawn_runup: float = 250.0

@export_group("Flight physics")

## Horizontal speed retained per second while flying from this jump, like the
## profile's air_drag. -1 = use the profile's GROUND drag_coefficient, so a
## ship keeps the speed it would have kept on the road. (The profile's
## air_drag, 0.161, is meant for a ship that has left the track by accident:
## it costs ~70 u/s over a one-second jump.)
@export var air_drag: float = -1.0

## Landing: the hover ray reaches 3x hover height, so a descending ship counts
## as "grounded" from ~8 m up, and from there the hover spring, not gravity,
## moves it. Stock, the spring then PULLS it down at up to hover_force_max
## (200 u/s^2, the pull that glues ships over crests) and the landing is a
## slam. While landing from a jump that pull is capped at this many times the
## profile's gravity (2 = what airborne gravity has ramped up to), so the ship
## keeps falling as it was until the spring takes its weight. < 0 = stock.
@export var landing_pull_limit_g: float = 2.0

## Multiplies the hover spring's damping while landing (profile damping 5.5 is
## a damping ratio of ~0.2 against stiffness 200: it bounces).
@export var landing_damping_scale: float = 3.0

## Multiplies hover_force_max while landing, so the spring can stop the
## descent before the hull touches the road.
@export var landing_force_scale: float = 2.0

## Seconds the ship must be settled (grounded, near hover height) before the
## landing ends and normal hover physics resume.
@export var landing_settle_time: float = 0.5
