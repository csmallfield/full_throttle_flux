extends Node

## Merge recorded laps into the developer library, then report how the trained
## AI compares with the best human laps.
##
## Run from the project root:
##     godot --headless --path . res://tools/import_recordings.tscn
##
## 1. Every *.zip in res://recordings_inbox/ (packages testers exported from
##    the main menu) is merged into res://recordings_library/, then moved to
##    res://recordings_inbox/processed/ so it is never imported twice.
## 2. Your own local laps (user://recordings/) are merged too, under your
##    tester id, so the library is the one place all laps live.
## 3. A benchmark prints, per track and ship, the best human flying lap
##    against the trained AI's measured peak.
##
## The library keeps RecordingStore.KEEP laps PER TESTER per bucket, so one
## prolific fast tester never crowds out a different line from someone else.

const INBOX := "res://recordings_inbox/"
const PROCESSED := "res://recordings_inbox/processed/"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(INBOX)
	DirAccess.make_dir_recursive_absolute(PROCESSED)
	DirAccess.make_dir_recursive_absolute(RecordingStore.LIBRARY_ROOT)
	
	print_rich("[b]Import recordings[/b]")
	_import_inbox()
	_import_local()
	_benchmark()
	get_tree().quit()

# ============================================================================
# IMPORT
# ============================================================================

func _import_inbox() -> void:
	var d := DirAccess.open(INBOX)
	var zips: Array[String] = []
	if d:
		for f in d.get_files():
			if f.to_lower().ends_with(".zip"):
				zips.append(f)
	if zips.is_empty():
		print("  inbox: no packages in %s" % INBOX)
		return
	for z in zips:
		var r := RecordingStore.import_package(INBOX + z)
		if r.has("error"):
			print("  %s: %s" % [z, r.error])
			continue
		print("  %s: tester %s, build %s -> %d laps read, %d kept, %d rejected" % [
			z, r.tester, r.build, r.imported, r.kept, r.rejected])
		DirAccess.rename_absolute(INBOX + z, PROCESSED + z)

func _import_local() -> void:
	var files := RecordingStore.all_files(RecordingStore.LOCAL_ROOT)
	var kept := 0
	for f in files:
		var rec := ResourceLoader.load(f, "", ResourceLoader.CACHE_MODE_IGNORE) as LapRecording
		if rec and RecordingStore.import_recording(rec).saved:
			kept += 1
	print("  local: %d laps read from %s, %d kept" % [files.size(), RecordingStore.LOCAL_ROOT, kept])

# ============================================================================
# BENCHMARK
# ============================================================================

## Library path: <root>/<track>/<ship>/<hash>/<mode>/<pool>/<tester>/<ms>_<ts>.res
## Everything needed is in the path, so no recording has to be loaded.
func _benchmark() -> void:
	var current := RecordingStore.current_profile_hashes()
	var best := {}   # "track|ship|mode" -> {time, tester}
	var buckets_stale := 0
	
	for f in RecordingStore.all_files(RecordingStore.LIBRARY_ROOT):
		var rel := f.trim_prefix(RecordingStore.LIBRARY_ROOT).split("/")
		if rel.size() < 7:
			continue
		var track := rel[0]
		var ship := rel[1]
		var hash := rel[2]
		var mode := rel[3]
		var pool := rel[4]
		var tester := rel[5]
		if pool != "flying":
			continue
		if current.get(ship, "") != hash:
			buckets_stale += 1
			continue
		var t := float(rel[6].get_slice("_", 0)) / 1000.0
		var key := "%s|%s|%s" % [track, ship, mode]
		if not best.has(key) or t < best[key].time:
			best[key] = {"time": t, "tester": tester}
	
	print_rich("\n[b]Benchmark[/b] - best human flying lap vs trained AI peak (current handling only)")
	if best.is_empty():
		print("  no current-handling flying laps in the library yet")
	var keys := best.keys()
	keys.sort()
	for key in keys:
		var parts: PackedStringArray = key.split("|")
		var track := parts[0]
		var ship := parts[1]
		var mode := parts[2]
		var human: Dictionary = best[key]
		var ai_text := "no trained line"
		var line := AILineTrainer.load_trained_line(track, ship)
		var human_time: float = human.time
		if line != null and line.trained_lap_time <= 0.0:
			ai_text = "AI trained line, time not recorded (re-run style_search)"
		elif line != null:
			var current_hash: String = current.get(ship, "")
			var fresh: bool = line.profile_hash.is_empty() or line.profile_hash == current_hash
			var delta: float = (line.trained_lap_time - human_time) / human_time * 100.0
			ai_text = "AI %.3fs (%+.1f%%)%s" % [line.trained_lap_time, delta,
					"" if fresh else "  STALE"]
		print("  %-22s %-14s %-11s human %.3fs [%s]   %s" % [
			track, ship, mode, human_time, human.tester, ai_text])
	if buckets_stale > 0:
		print("  (%d laps skipped: recorded on older handling, kept as archive)" % buckets_stale)
