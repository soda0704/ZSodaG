class_name ElevatorRollupDoor
extends Node3D

signal motion_finished(opened: bool)

@export var animation_duration: float = 1.5
@export var starts_open: bool = false
@export var internal_collision_enabled: bool = true

var is_open: bool = false

@onready var animation_player: AnimationPlayer = %AnimationPlayer
@onready var internal_collision: CollisionShape3D = %InternalCollision


func _ready() -> void:
	animation_player.animation_finished.connect(_on_animation_finished)
	set_open(starts_open, true)


func set_open(value: bool, instant: bool = false) -> void:
	is_open = value
	animation_player.speed_scale = 1.0 / maxf(animation_duration, 0.01)
	if value:
		_set_internal_collision_closed(false)
	if instant:
		animation_player.play(&"open")
		animation_player.seek(
			animation_player.get_animation(&"open").length if value else 0.0,
			true
		)
		animation_player.pause()
		_set_internal_collision_closed(not value)
		return
	if value:
		animation_player.play(&"open")
	else:
		animation_player.play_backwards(&"open")


func _set_internal_collision_closed(value: bool) -> void:
	if is_instance_valid(internal_collision):
		internal_collision.disabled = not (
			value and internal_collision_enabled
		)


func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name != &"open":
		return
	_set_internal_collision_closed(not is_open)
	motion_finished.emit(is_open)
