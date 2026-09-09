extends StaticBody3D

var health: float = 100.0
var _label: Label3D
var _reset_left: float = 0.0

func _ready() -> void:
	collision_layer = 1
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.15, 1.3, 0.65)
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("c37d36")
	mesh.material_override = material
	add_child(mesh)
	var shape := CollisionShape3D.new()
	var collision := BoxShape3D.new()
	collision.size = box.size
	shape.shape = collision
	add_child(shape)
	_label = Label3D.new()
	add_child(_label)
	_label.position.y = 0.85
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 38
	_label.text = "МИШЕНЬ · 100"

func apply_weapon_damage(amount: float) -> void:
	if not multiplayer.is_server() or health <= 0.0:
		return
	health = maxf(0.0, health - amount)
	_reset_left = 3.0
	_sync.rpc(health)

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or _reset_left <= 0.0:
		return
	_reset_left -= delta
	if _reset_left <= 0.0:
		_sync.rpc(100.0)

@rpc("authority", "call_local", "reliable", 2)
func _sync(value: float) -> void:
	health = value
	_label.text = "ПОРАЖЕНА" if health == 0.0 else "МИШЕНЬ · %d" % int(health)
