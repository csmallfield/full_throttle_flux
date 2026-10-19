@tool
extends Resource
class_name UtopiaGreebleZone
## A stretch of track dressed with one style. Distances are along the Road
## rail (within a few metres of MainSpline distance). from > to wraps past
## the start line.
@export var label := "zone"
@export var from_d := 0.0
@export var to_d := 100.0
@export var style: UtopiaGreebleStyle
## Swap left/right for side-specific rules (e.g. chevrons on the outside of a
## left-hand vs right-hand hairpin).
@export var mirror := false
## Multiplies every rule's probability in this zone.
@export_range(0.0, 2.0) var density := 1.0
@export var seed := 1
