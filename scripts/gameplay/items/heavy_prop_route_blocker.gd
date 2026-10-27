extends StaticBody3D
## A scene-authored player clearance gate for the initial obstructing placement.
## It never collides with the carried prop, interaction rays or bullets.
@export_node_path("RigidBody3D") var prop_path: NodePath
@export_range(0.1, 2.0) var clearance_distance := .35
@export_range(5.0, 90.0) var clearance_angle_degrees := 20.0
@onready var prop: HeavyCarryProp = get_node(prop_path)
@onready var shape: CollisionShape3D = $CollisionShape3D
var initial_pose := Transform3D.IDENTITY
var cleared := false

func _ready() -> void:
	initial_pose = prop.global_transform
	if not multiplayer.is_server(): _request_clearance.call_deferred()

func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server() or cleared: return
	var moved := prop.global_position.distance_to(initial_pose.origin) >= clearance_distance
	var turn := initial_pose.basis.orthonormalized().get_rotation_quaternion().angle_to(prop.global_basis.orthonormalized().get_rotation_quaternion())
	if bool(prop.item_state.get("obstruction_cleared", false)) or moved or turn >= deg_to_rad(clearance_angle_degrees):
		prop.item_state["obstruction_cleared"] = true
		_set_cleared.rpc(true)

@rpc("authority", "call_local", "reliable", 2)
func _set_cleared(value: bool) -> void:
	cleared = value
	shape.set_deferred("disabled", value)

func _request_clearance() -> void:
	_request_clearance_state.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable", 2)
func _request_clearance_state() -> void:
	if multiplayer.is_server(): _set_cleared.rpc_id(multiplayer.get_remote_sender_id(), cleared)
