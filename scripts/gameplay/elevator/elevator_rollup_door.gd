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
	$DoorAudio.play()
	if value:
		animation_player.play(&"open")
	else:
		animation_player.play_backwards(&"open")


func _set_internal_collision_closed(value: bool) -> void:
	if is_instance_valid(internal_collision):
		internal_collision.disabled = not (
			value and internal_collision_enabled
		)


func get_network_snapshot() -> Dictionary:
	return {
		"open": is_open,
		"position": animation_player.current_animation_position,
		"moving": animation_player.is_playing(),
	}


func apply_network_snapshot(snapshot: Dictionary, age_seconds: float = 0.0) -> void:
	var next_open := bool(snapshot.get("open", false))
	var moving := bool(snapshot.get("moving", false))
	var changed := is_open != next_open
	is_open = next_open
	animation_player.speed_scale = 1.0 / maxf(animation_duration, 0.01)
	var clip_length := animation_player.get_animation(&"open").length
	if moving:
		if next_open:
			animation_player.play(&"open")
		else:
			animation_player.play_backwards(&"open")
		var direction := 1.0 if next_open else -1.0
		animation_player.seek(clampf(
			float(snapshot.get("position", 0.0)) + direction * age_seconds * animation_player.speed_scale,
			0.0, clip_length
		), true)
		if changed:
			$DoorAudio.play()
	else:
		set_open(next_open, true)
	_set_internal_collision_closed(not next_open and not moving)


func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name != &"open":
		return
	_set_internal_collision_closed(not is_open)
	motion_finished.emit(is_open)
