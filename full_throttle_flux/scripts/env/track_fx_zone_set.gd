@tool
extends Resource
class_name TrackFxZoneSet
## A saved list of TrackFxZones (v35), usually GENERATED, e.g. the covered
## spans written by tools/env/survey_cover.gd. Kept apart from hand-authored
## zones so re-running a survey never overwrites anything you placed yourself.

## What produced this set and when (informational).
@export var source: String = ""

@export var zones: Array[TrackFxZone] = []
