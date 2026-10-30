extends Control
## Screen effect belongs to the local player's active camera, below the HUD.
@export var effect_enabled := true:
	set(value):
		effect_enabled = value
		if is_node_ready(): _update_visibility()

@onready var player: GamePlayer = get_parent().get_parent()
@onready var camera: Camera3D = player.get_node("Head/Camera3D")

func _ready() -> void:
	_update_visibility()

func _process(_delta: float) -> void:
	_update_visibility()

func _update_visibility() -> void:
	visible = effect_enabled and player.is_local_player() and camera.is_current()
