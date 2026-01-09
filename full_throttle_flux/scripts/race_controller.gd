extends Node
class_name RaceController

## Controls the race flow: countdown, ship locking, pause handling
## Coordinates with MusicPlaylistManager for race music

@export var ship: AGShip2097
@export var pause_menu: PauseMenu

var ship_locked := true
var initial_ship_position: Vector3
var initial_ship_rotation: Basis
var race_ended := false
var final_ship_position: Vector3
var final_ship_rotation: Basis

# Now Playing display instance
var now_playing_display: NowPlayingDisplay

func _ready() -> void:
	# Store initial ship state
	if ship:
		initial_ship_position = ship.global_position
		initial_ship_rotation = ship.global_transform.basis
		ship.velocity = Vector3.ZERO
	
	# Connect signals
	RaceManager.race_started.connect(_on_race_started)
	RaceManager.countdown_tick.connect(_on_countdown_tick)
	RaceManager.race_finished.connect(_on_race_finished)
	RaceManager.endless_finished.connect(_on_endless_finished)
	
	# Add the NowPlayingDisplay to the race scene
	_setup_now_playing_display()
	
	# Start countdown after a brief delay
	await get_tree().create_timer(1.0).timeout
	RaceManager.start_countdown()

func _setup_now_playing_display() -> void:
	# Add the NowPlayingDisplay to this scene (deferred to avoid busy parent error)
	var display_scene = preload("res://scenes/now_playing_display.tscn")
	now_playing_display = display_scene.instantiate()
	get_parent().call_deferred("add_child", now_playing_display)

func _physics_process(delta: float) -> void:
	if ship:
		if ship_locked and not race_ended:
			# Lock ship in place during countdown
			ship.velocity = Vector3.ZERO
			ship.global_position = initial_ship_position
			ship.global_transform.basis = initial_ship_rotation
		elif race_ended:
			# Lock ship at final position after race ends
			# Apply strong drag to bring ship to a stop
			ship.velocity = ship.velocity.lerp(Vector3.ZERO, 5.0 * delta)
			
			# Once nearly stopped, lock in place
			if ship.velocity.length() < 1.0:
				ship.velocity = Vector3.ZERO

func _input(event: InputEvent) -> void:
	# Don't process pause if race has ended
	if race_ended:
		return
	
	# Handle pause
	if event.is_action_pressed("ui_cancel"):  # ESC
		if RaceManager.is_racing() and pause_menu:
			pause_menu.show_pause()
			get_viewport().set_input_as_handled()

func _on_countdown_tick(number: int) -> void:
	# Keep ship locked during countdown
	ship_locked = (number > 0)

func _on_race_started() -> void:
	# Unlock ship
	ship_locked = false
	race_ended = false
	
	# Start race music via the playlist manager
	MusicPlaylistManager.start_race_music()

func _on_race_finished(_total_time: float, _best_lap: float) -> void:
	# Lock ship controls at race end
	race_ended = true
	if ship:
		ship.lock_controls()
		final_ship_position = ship.global_position
		final_ship_rotation = ship.global_transform.basis

func _on_endless_finished(_total_laps: int, _total_time: float, _best_lap: float) -> void:
	# Lock ship controls at endless mode end
	race_ended = true
	if ship:
		ship.lock_controls()
		final_ship_position = ship.global_position
		final_ship_rotation = ship.global_transform.basis
