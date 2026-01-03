extends Node
class_name RaceController

## Controls the race flow: countdown, ship locking, pause handling

@export var ship: AGShip2097
@export var pause_menu: PauseMenu

var ship_locked := true
var initial_ship_position: Vector3
var initial_ship_rotation: Basis

func _ready() -> void:
	# Store initial ship state
	if ship:
		initial_ship_position = ship.global_position
		initial_ship_rotation = ship.global_transform.basis
		ship.velocity = Vector3.ZERO
	
	# Connect signals
	RaceManager.race_started.connect(_on_race_started)
	RaceManager.countdown_tick.connect(_on_countdown_tick)
	
	# Start countdown after a brief delay
	await get_tree().create_timer(1.0).timeout
	RaceManager.start_countdown()

func _physics_process(_delta: float) -> void:
	if ship_locked and ship:
		# Lock ship in place during countdown
		ship.velocity = Vector3.ZERO
		ship.global_position = initial_ship_position
		ship.global_transform.basis = initial_ship_rotation

func _input(event: InputEvent) -> void:
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
