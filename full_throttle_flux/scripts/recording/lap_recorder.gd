extends Node
class_name LapRecorder

## Records every lap the player drives, automatically, and hands each finished
## lap to RecordingStore, which keeps the best RecordingStore.KEEP per bucket.
##
## Added by ModeBase to the player's ship. Does nothing unless the ship's
## profile has `recordable` set -- turn that on only once a ship is a real
## candidate for the game, so laps driven on a profile you are still
## inventing never pollute the data.
##
## Lap boundaries and lap times come from RaceManager.lap_completed, the same
## event the HUD uses, so a recorded lap time always matches what the player
## saw. RaceManager fires it exactly once per player lap in every mode.

signal lap_saved(recording: LapRecording, rank: int)
signal lap_rejected(reason: String)

## Seconds between samples. 0.05 = 20Hz, ~1200 samples for a 60s lap.
@export var sample_interval: float = 0.05

## Laps covering less of the track than this are rejected as cut or broken.
@export var min_coverage: float = 0.90

## Print one line per lap to the console.
@export var verbose: bool = true

var ship: ShipController
var track_root: Node
var mode_name: String = ""

var _helper: TrackSplineHelper
var _active: bool = false
var _enabled: bool = false
var _accum: float = 0.0
var _lap_clock: float = 0.0
var _bins := PackedByteArray()
var _rec: LapRecording

const COVERAGE_BINS := 100

func _ready() -> void:
	if ship == null or ship.profile == null:
		return
	if not ship.profile.recordable:
		if verbose:
			print("LapRecorder: %s is not recordable - not recording" % ship.profile.ship_id)
		return
	if track_root == null:
		return
	_helper = TrackSplineHelper.new(track_root)
	if not _helper.is_valid:
		push_warning("LapRecorder: no valid spline, cannot record")
		return
	
	_enabled = true
	var rm := get_node_or_null("/root/RaceManager")
	if rm:
		rm.race_started.connect(_begin_lap)
		rm.lap_completed.connect(_on_lap_completed)
	if verbose:
		print("LapRecorder: recording %s on %s (%s), profile %s" % [
			ship.profile.ship_id, _track_id(), mode_name, ship.profile.handling_hash()])

func _track_id() -> String:
	return AILineTrainer.track_id_for(track_root)

# ============================================================================
# LAP LIFECYCLE
# ============================================================================

func _begin_lap() -> void:
	if not _enabled:
		return
	_rec = LapRecording.new()
	_rec.sample_interval = sample_interval
	_bins = PackedByteArray()
	_bins.resize(COVERAGE_BINS)
	_accum = 0.0
	_lap_clock = 0.0
	_active = true
	_sample()   # the first sample sits on the line

func _on_lap_completed(lap_number: int, lap_time: float) -> void:
	complete_lap(lap_number, lap_time)

## Finish the lap in progress and start the next one. Public so tests and
## other modes can drive it without RaceManager.
func complete_lap(lap_number: int, lap_time: float) -> void:
	if not _enabled or not _active or _rec == null:
		_begin_lap()
		return
	
	var rec := _rec
	rec.track_id = _track_id()
	rec.ship_id = ship.profile.ship_id
	rec.profile_hash = ship.profile.handling_hash()
	rec.mode = mode_name
	rec.lap_number = lap_number
	rec.standing_start = lap_number <= 1
	rec.lap_time = lap_time
	rec.build_version = RecordingStore.build_version()
	rec.recorded_at = int(Time.get_unix_time_from_system())
	rec.tester_id = RecordingStore.tester_id()
	rec.coverage = _coverage()
	
	# Start the next lap before any disk work, so no samples are lost.
	_begin_lap()
	
	if rec.coverage < min_coverage:
		var why := "coverage %.0f%% < %.0f%%" % [rec.coverage * 100.0, min_coverage * 100.0]
		if verbose:
			print("LapRecorder: rejected L%d %.3fs (%s)" % [lap_number, lap_time, why])
		lap_rejected.emit(why)
		return
	
	var result := RecordingStore.save_lap(rec)
	if verbose:
		if result.saved:
			print("LapRecorder: L%d%s %.3fs kept, rank %d of %d (%s)" % [
				lap_number, "s" if rec.standing_start else "", lap_time,
				result.rank, RecordingStore.KEEP, rec.pool()])
		else:
			print("LapRecorder: L%d %.3fs not in the top %d" % [
				lap_number, lap_time, RecordingStore.KEEP])
	lap_saved.emit(rec, result.rank)

## Stop recording for good. Called when the player's ship is handed over to
## the AI at the finish, so the cool-down laps the AI flies are never filed as
## the player's.
func stop() -> void:
	_active = false
	_enabled = false

# ============================================================================
# SAMPLING
# ============================================================================

func _physics_process(delta: float) -> void:
	if not _active or not is_instance_valid(ship):
		return
	_lap_clock += delta
	_accum += delta
	if _accum >= sample_interval:
		_accum -= sample_interval
		_sample()

func _sample() -> void:
	var pos := ship.global_position
	var offset: float = _helper.world_to_spline_offset(pos)
	_rec.t.append(_lap_clock)
	_rec.spline_offset.append(offset)
	_rec.lateral.append(_helper.calculate_lateral_offset(pos, offset, true))
	_rec.speed.append(ship.velocity.length())
	_rec.throttle.append(ship.throttle_input)
	_rec.steer.append(ship.steer_input)
	_rec.airbrake_left.append(ship.airbrake_left)
	_rec.airbrake_right.append(ship.airbrake_right)
	_rec.positions.append(pos)
	_bins[clampi(int(offset * COVERAGE_BINS), 0, COVERAGE_BINS - 1)] = 1

func _coverage() -> float:
	var hit := 0
	for b in _bins:
		hit += b
	return float(hit) / float(COVERAGE_BINS)
