extends Resource
class_name LapRecording

## One recorded lap by a player.
##
## Recordings are a DATA SOURCE, never AI control. Since v17 nothing in the AI
## steers by them -- they exist to troubleshoot AI behaviour against how
## humans actually drive a track, to benchmark the trained AI against the best
## human laps, and to surface strategies nobody has thought of yet.
##
## Samples are stored as parallel packed arrays rather than an array of
## sample objects: a 60s lap at 20Hz is ~1200 samples, and packed arrays save
## compactly to binary .res and load without allocating 1200 objects.

const FORMAT_VERSION := 1

@export var format_version: int = FORMAT_VERSION

# ============================================================================
# IDENTITY -- together these decide which bucket a lap is ranked in
# ============================================================================

@export var track_id: String = ""
@export var ship_id: String = ""

## ShipProfile.handling_hash() at the time of recording. A lap driven on a
## different handling model is not comparable, so laps only ever rank against
## laps with the same hash.
@export var profile_hash: String = ""

## "time_trial", "endless" or "race". Race laps are contaminated by traffic
## and avoidance, so modes rank separately.
@export var mode: String = ""

# ============================================================================
# THE LAP
# ============================================================================

@export var lap_number: int = 0

## Lap 1 starts from the grid. Never ranked against flying laps.
@export var standing_start: bool = false

## Authoritative lap time from RaceManager, seconds.
@export var lap_time: float = 0.0

## Fraction of the track the samples actually cover, 0..1. A lap whose
## samples skip a large part of the circuit was cut or teleported, and is
## rejected rather than stored.
@export var coverage: float = 0.0

# ============================================================================
# PROVENANCE
# ============================================================================

@export var build_version: String = ""

## Unix time.
@export var recorded_at: int = 0

## Anonymous, persistent per-install id (RecordingStore.tester_id()). Lets a
## merged library keep each tester's best laps separately, so one prolific
## fast tester cannot crowd out a different, faster strategy from someone else.
@export var tester_id: String = ""

# ============================================================================
# TELEMETRY
# ============================================================================

@export var sample_interval: float = 0.05

## Seconds since the start of this lap.
@export var t: PackedFloat32Array = PackedFloat32Array()

## TrackSplineHelper offset, normalised 0..1.
@export var spline_offset: PackedFloat32Array = PackedFloat32Array()

## Meters from the spline centreline, same convention as BakedRacingLine.
@export var lateral: PackedFloat32Array = PackedFloat32Array()

@export var speed: PackedFloat32Array = PackedFloat32Array()
@export var throttle: PackedFloat32Array = PackedFloat32Array()
@export var steer: PackedFloat32Array = PackedFloat32Array()
@export var airbrake_left: PackedFloat32Array = PackedFloat32Array()
@export var airbrake_right: PackedFloat32Array = PackedFloat32Array()

## World positions, for drawing the line in-editor when troubleshooting.
@export var positions: PackedVector3Array = PackedVector3Array()

func sample_count() -> int:
	return t.size()

func pool() -> String:
	return "standing" if standing_start else "flying"

func describe() -> String:
	return "%s / %s / %s / %s  L%d%s  %.3fs  (%d samples, %.0f%% coverage, tester %s)" % [
		track_id, ship_id, profile_hash, mode, lap_number,
		"s" if standing_start else "", lap_time, sample_count(),
		coverage * 100.0, tester_id]
