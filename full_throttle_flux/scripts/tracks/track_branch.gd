@tool
extends Resource
class_name TrackBranch

## An alternative route (v31). The MainSpline stays the canonical lap; a branch
## is a second Path3D that leaves it at `fork_distance` and comes back at
## `rejoin_distance` (metres along the MainSpline). Owned by a TrackGraph.
##
## Lap progress, race positions and respawns all work in MAIN distance, so a
## ship on a branch is given the main-lap distance its branch distance maps to.
## The map is piecewise linear with slope 1 over the junctions, where the
## branch and the main road physically overlap: there the nearest-path choice
## can flip either way without moving the progress, and progress never jumps
## crossing between main and branch. Between the junctions it is linear
## (a shortcut's metres count for more than one main metre each).
##
##   main:   ...fork ===== A (main route) ===== rejoin...
##   branch:      fork ==== B (branch) ==== rejoin
##   map:    b in [0, fork_blend]            -> fork + b
##           b in [L - rejoin_blend, L]      -> rejoin - (L - b)
##           in between                      -> linear

@export var branch_name: String = "Branch"

## The branch's Path3D, relative to the TrackGraph node. Its curve starts on
## the MainSpline at fork_distance and ends on it at rejoin_distance.
@export var path: NodePath

@export_group("Junctions (metres)")

## Main distance where the branch leaves.
@export var fork_distance: float = 0.0

## Main distance where the branch comes back. May be < fork_distance if the
## branch spans the lap seam.
@export var rejoin_distance: float = 0.0

## Branch metres from the fork over which branch and main overlap (the
## junction). Mapped 1:1 onto main metres.
@export var fork_blend: float = 150.0

## Branch metres before the rejoin over which they overlap again.
@export var rejoin_blend: float = 150.0

@export_group("Route lap (v32)")

## A whole-lap Path3D that runs main -> this branch -> main (relative to the
## TrackGraph). The AI's racing line, its trainer and the cinematic rig work
## along one lap spline at a time; this is the one for the shortcut route.
## Logic only (no geometry). Empty = no route lap.
@export var route_path: NodePath

## Route-lap distance of the fork and of the rejoin. Before route_fork and
## after route_rejoin the route lap is the MainSpline (offset by the
## difference in length after the rejoin); between them it is the branch.
@export var route_fork: float = 0.0
@export var route_rejoin: float = 0.0
