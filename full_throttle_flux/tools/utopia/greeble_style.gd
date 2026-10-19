@tool
extends Resource
class_name UtopiaGreebleStyle
## A dressing style: a bay length plus rules for every layer. Save styles as
## .tres and reuse them across zones; tweak one and every zone using it
## changes on the next Rebuild.
@export var style_name := "style"
## Shared rhythm for every rule in the style, in metres along the road.
@export var bay_length := 24.0
@export var rules: Array[UtopiaGreebleRule] = []
## Optional overhead marker placed at the START of each zone using this style
## (a portal that announces the district). Skipped inside tunnels.
@export var threshold_mesh: Mesh
