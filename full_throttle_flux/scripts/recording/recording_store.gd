extends RefCounted
class_name RecordingStore

## Where player lap recordings live, how they are ranked, and how they move
## between a tester's machine and the developer's library.
##
## LAYOUT
## ---------------------------------------------------------------------------
##   <root>/<track>/<ship>/<profile_hash>/<mode>/<pool>/<ms>_<unix>.res
##
## pool is "flying" or "standing". The file name starts with the lap time in
## milliseconds, zero padded, so a plain lexical sort IS the ranking.
##
## Each leaf keeps the best KEEP laps. A handling change produces a new
## profile_hash and therefore a fresh bucket: older buckets are not deleted,
## they simply stop being current -- an archive for free.
##
## The developer library adds one more level, <tester_id>/, below <pool>, and
## applies KEEP per tester. That keeps each tester's best laps even when
## another tester is consistently faster, so a genuinely different fast line
## from someone new is never crowded out.

## Laps kept per bucket (per tester, in the library).
const KEEP := 10

const LOCAL_ROOT := "user://recordings/"
const LIBRARY_ROOT := "res://recordings_library/"
const TESTER_FILE := "user://tester.cfg"
const MANIFEST_NAME := "manifest.json"
const PACKAGE_FORMAT := 1

# ============================================================================
# IDENTITY
# ============================================================================

## Anonymous per-install tester id, created on first use. Deliberately not
## the OS user name, which is often a real name.
static func tester_id() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(TESTER_FILE) == OK:
		var existing: String = cfg.get_value("tester", "id", "")
		if not existing.is_empty():
			return existing
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var id := "%08x" % (rng.randi() & 0xFFFFFFFF)
	cfg.set_value("tester", "id", id)
	cfg.set_value("tester", "name", "")  # optional, edit by hand if wanted
	cfg.save(TESTER_FILE)
	return id

static func build_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "unknown"))

# ============================================================================
# PATHS
# ============================================================================

static func bucket_dir(root: String, rec: LapRecording, tester: String = "") -> String:
	var parts: Array[String] = [
		rec.track_id.validate_filename(), rec.ship_id.validate_filename(),
		rec.profile_hash.validate_filename(), rec.mode.validate_filename(), rec.pool()]
	if not tester.is_empty():
		parts.append(tester.validate_filename())
	return root.path_join("/".join(parts)) + "/"

static func file_name(rec: LapRecording) -> String:
	return "%09d_%d.res" % [int(round(rec.lap_time * 1000.0)), rec.recorded_at]

# ============================================================================
# SAVING (the player's own machine)
# ============================================================================

## Store a lap if it makes the top KEEP for its bucket. Returns a dictionary:
##   saved: bool, rank: int (1-based, -1 if not kept), path: String
static func save_lap(rec: LapRecording, root: String = LOCAL_ROOT, tester: String = "") -> Dictionary:
	var dir := bucket_dir(root, rec, tester)
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir + file_name(rec)
	var err := ResourceSaver.save(rec, path, ResourceSaver.FLAG_COMPRESS)
	if err != OK:
		push_warning("RecordingStore: failed to save %s (error %d)" % [path, err])
		return {"saved": false, "rank": -1, "path": ""}
	_trim(dir)
	var files := _ranked_files(dir)
	var rank := files.find(path.get_file()) + 1
	return {"saved": rank > 0, "rank": rank if rank > 0 else -1, "path": path}

## Delete everything below the top KEEP in one bucket directory.
static func _trim(dir: String) -> void:
	var files := _ranked_files(dir)
	for i in range(KEEP, files.size()):
		DirAccess.remove_absolute(dir + files[i])

static func _ranked_files(dir: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".res"):
			out.append(f)
	out.sort()
	return out

## Every recording file under a root, recursively.
static func all_files(root: String) -> Array[String]:
	var out: Array[String] = []
	_walk(root, out)
	return out

static func _walk(dir: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".res"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		_walk(dir.path_join(sub), out)

# ============================================================================
# EXPORT (tester -> developer)
# ============================================================================

## Handling hashes of every ship currently marked recordable, keyed by ship_id.
static func current_profile_hashes() -> Dictionary:
	var out := {}
	for dir in ["res://resources/ships/", "res://resources/ships/hidden/"]:
		var d := DirAccess.open(dir)
		if d == null:
			continue
		for f in d.get_files():
			var clean := f.trim_suffix(".remap")
			if not clean.ends_with(".tres"):
				continue
			var p := load(dir + clean) as ShipProfile
			if p and p.recordable:
				out[p.ship_id] = p.handling_hash()
	return out

## Zip every local recording plus a manifest into one file the tester can
## send. Returns the path written, or "" on failure.
static func export_package() -> String:
	var files := all_files(LOCAL_ROOT)
	var tester := tester_id()
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	var name := "FTF_recordings_%s_%s.zip" % [tester, stamp]
	
	var out_dir := OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
	if out_dir.is_empty() or not DirAccess.dir_exists_absolute(out_dir):
		out_dir = ProjectSettings.globalize_path("user://")
	var out_path := out_dir.path_join(name)
	
	var zip := ZIPPacker.new()
	if zip.open(out_path) != OK:
		push_warning("RecordingStore: could not create %s" % out_path)
		return ""
	
	var manifest := {
		"package_format": PACKAGE_FORMAT,
		"tester_id": tester,
		"build_version": build_version(),
		"exported_at": Time.get_unix_time_from_system(),
		"profile_hashes": current_profile_hashes(),
		"lap_count": files.size(),
	}
	zip.start_file(MANIFEST_NAME)
	zip.write_file(JSON.stringify(manifest, "\t").to_utf8_buffer())
	zip.close_file()
	
	for f in files:
		var rel := f.trim_prefix(LOCAL_ROOT)
		zip.start_file("laps/" + rel)
		zip.write_file(FileAccess.get_file_as_bytes(f))
		zip.close_file()
	zip.close()
	return out_path

# ============================================================================
# IMPORT (developer side)
# ============================================================================

## Merge one exported package into the library. Returns a summary.
static func import_package(zip_path: String, library_root: String = LIBRARY_ROOT) -> Dictionary:
	var result := {"imported": 0, "kept": 0, "rejected": 0, "tester": "", "build": ""}
	var zip := ZIPReader.new()
	if zip.open(zip_path) != OK:
		result["error"] = "cannot open"
		return result
	
	var manifest := {}
	if zip.file_exists(MANIFEST_NAME):
		var parsed = JSON.parse_string(zip.read_file(MANIFEST_NAME).get_string_from_utf8())
		if parsed is Dictionary:
			manifest = parsed
	result["tester"] = manifest.get("tester_id", "unknown")
	result["build"] = manifest.get("build_version", "unknown")
	
	var tmp := "user://_import_tmp.res"
	for entry in zip.get_files():
		if not entry.begins_with("laps/") or not entry.ends_with(".res"):
			continue
		var f := FileAccess.open(tmp, FileAccess.WRITE)
		f.store_buffer(zip.read_file(entry))
		f.close()
		var rec := ResourceLoader.load(tmp, "", ResourceLoader.CACHE_MODE_IGNORE) as LapRecording
		if rec == null or rec.format_version != LapRecording.FORMAT_VERSION:
			result.rejected += 1
			continue
		result.imported += 1
		if import_recording(rec, library_root).saved:
			result.kept += 1
	zip.close()
	DirAccess.remove_absolute(tmp)
	return result

## Place one recording in the library, under its tester, ranked per tester.
static func import_recording(rec: LapRecording, library_root: String = LIBRARY_ROOT) -> Dictionary:
	var tester := rec.tester_id if not rec.tester_id.is_empty() else "unknown"
	return save_lap(rec, library_root, tester)
