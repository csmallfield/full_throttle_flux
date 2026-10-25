@tool
extends UtopiaGreebleZone
class_name TrackGreebleZone
## One resolved greeble zone of a Track Builder track (v36), written by the
## Track Builder from a GreebleZoneKey (or inherited by a branch from the main
## track at its fork). Distances are along the spline `path_index` names in
## TrackGreebles.paths (0 = MainSpline), not the Utopia Road rail.
##
## Never edit these by hand: move or change the GreebleZoneKey and the
## builder rewrites them.

## Index into TrackGreebles.paths.
@export var path_index := 0
## Layers left out in this zone (bit per layer: TrackGreebles.LAYER_BITS).
@export var skip_layers := 0
## The GreebleZoneKey this came from (for reports and the validator).
@export var key_name := ""
