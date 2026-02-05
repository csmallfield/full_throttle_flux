@tool
extends Resource
class_name TrackManifest

## Resource that holds references to all track profiles in the game.
## This is used instead of directory scanning because exported builds
## cannot iterate over res:// directories (they're packed into a PCK file).
##
## HOW TO USE:
## 1. Create TrackProfile .tres files for each track in res://resources/tracks/
## 2. Create a track_manifest.tres file (right-click in FileSystem → New Resource → TrackManifest)
## 3. In the Inspector, add all your TrackProfile resources to the "tracks" array
## 4. Save the manifest - GameManager will load it automatically from res://resources/tracks/track_manifest.tres

## Path where GameManager looks for this manifest
const MANIFEST_PATH := "res://resources/tracks/track_manifest.tres"

## List of all track profile resources in the game
@export var tracks: Array[TrackProfile] = []

## Get all valid tracks
func get_all_tracks() -> Array[TrackProfile]:
	var result: Array[TrackProfile] = []
	for track in tracks:
		if track:
			result.append(track)
	return result

## Get tracks that support a specific mode
func get_tracks_for_mode(mode_id: String) -> Array[TrackProfile]:
	var result: Array[TrackProfile] = []
	for track in tracks:
		if track:
			var supported = track.get_supported_modes()
			if mode_id in supported:
				result.append(track)
	return result

## Get track by ID
func get_track_by_id(track_id: String) -> TrackProfile:
	for track in tracks:
		if track and track.track_id == track_id:
			return track
	return null

## Get count of valid tracks
func get_valid_track_count() -> int:
	var count := 0
	for track in tracks:
		if track:
			count += 1
	return count
