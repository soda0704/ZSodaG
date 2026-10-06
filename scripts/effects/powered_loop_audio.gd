extends AudioStreamPlayer3D

@export var running_volume_db := -8.0
@export_range(0.1, 5.0) var fade_seconds := 0.8
var _power: BaseGameplayController

func _ready() -> void:
	_bind.call_deferred()

func _bind() -> void:
	_power = get_tree().get_first_node_in_group("base_gameplay_controller")

func _process(delta: float) -> void:
	var powered := _power != null and _power.main_breaker_on
	AudioFade.apply(self, db_to_linear(running_volume_db) if powered else 0.0, delta, fade_seconds)

