extends Node3D
## Native child scenes own every model/material/transform; the snapshot selects one.
@export var lamp_animation_path := NodePath("../UVLamp/PowerAnimation")
@onready var lamp_animation: AnimationPlayer = get_node(lamp_animation_path)
var _lamp_powered := -1
@export var live_root_path := NodePath("Live")
@export var dead_root_path := NodePath("Dead")
@onready var live_root: Node3D = get_node(live_root_path)
@onready var dead_root: Node3D = get_node(dead_root_path)
var _controller: BaseGameplayController

func _ready() -> void:
	_bind.call_deferred()

func _bind() -> void:
	_controller = get_tree().get_first_node_in_group("base_gameplay_controller") as BaseGameplayController
	if _controller == null: return
	_controller.snapshot_changed.connect(_apply)
	_apply(_controller.get_snapshot())

func _apply(snapshot: Dictionary) -> void:
	var powered := bool(snapshot.get("main_breaker_on", false)) and not bool((snapshot.get("containment", {}) as Dictionary).get("fault", false))
	if int(powered) != _lamp_powered:
		_lamp_powered = int(powered)
		lamp_animation.play(&"on" if powered else &"off")
		lamp_animation.advance(0.0)
	var planted := bool(snapshot.get("plant_seed_planted", false))
	var dead := bool(snapshot.get("plant_withered", false))
	var stage := clampi(int(snapshot.get("plant_growth_stage", 0)), 0, BaseGameplayController.PLANT_FINAL_STAGE)
	for index in live_root.get_child_count():
		(live_root.get_child(index) as Node3D).visible = planted and not dead and stage == index + 1
	for index in dead_root.get_child_count():
		(dead_root.get_child(index) as Node3D).visible = planted and dead and maxi(stage, 1) == index + 1
