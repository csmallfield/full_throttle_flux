@tool
extends Resource
class_name TrackSurfaceZone
## One resolved track surface zone of a Track Builder track (v38 phase 3),
## written by the Track Builder from a SurfaceZoneKey (or inherited by a
## branch from the main track at its fork). Distances are along the spline
## `path_index` names in TrackSurface.paths (0 = MainSpline).
##
## Never edit these by hand: move or change the SurfaceZoneKey and the
## builder rewrites them.

@export var path_index := 0
@export var from_d := 0.0
@export var to_d := 0.0
@export var profile: TrackSurfaceProfile
## Metres over which this zone cross-fades in from the one before; 0 = a
## hard seam.
@export var blend_in := 0.0
## 0..1023, varies the panel and vent hashes per zone.
@export var seed := 0
## Wear multiplier (v38 phase 4): 0 = factory clean, 1 = the track's age,
## 2 = twice as worn.
@export var wear := 1.0
## The SurfaceZoneKey this came from (for reports and the validator).
@export var key_name := ""
