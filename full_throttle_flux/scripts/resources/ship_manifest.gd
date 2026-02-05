@tool
extends Resource
class_name ShipManifest

## Resource that holds references to all ship profiles in the game.
## This is used instead of directory scanning because exported builds
## cannot iterate over res:// directories (they're packed into a PCK file).
##
## HOW TO USE:
## 1. Create ShipProfile .tres files for each ship in res://resources/ships/
## 2. Create a ship_manifest.tres file (right-click in FileSystem → New Resource → ShipManifest)
## 3. In the Inspector, add all your ShipProfile resources to the "ships" array
## 4. Save the manifest - GameManager will load it automatically from res://resources/ships/ship_manifest.tres

## Path where GameManager looks for this manifest
const MANIFEST_PATH := "res://resources/ships/ship_manifest.tres"

## List of all ship profile resources in the game
@export var ships: Array[ShipProfile] = []

## Get all valid ships
func get_all_ships() -> Array[ShipProfile]:
	var result: Array[ShipProfile] = []
	for ship in ships:
		if ship:
			result.append(ship)
	return result

## Get ship by ID
func get_ship_by_id(ship_id: String) -> ShipProfile:
	for ship in ships:
		if ship and ship.ship_id == ship_id:
			return ship
	return null

## Get count of valid ships
func get_valid_ship_count() -> int:
	var count := 0
	for ship in ships:
		if ship:
			count += 1
	return count
