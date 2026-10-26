extends StaticBody3D
## Temporary hive art: a frozen pose of the existing tailed creature, without AI.
@export_range(0, 2) var hive_index := 0
@export_range(0.0, 2.8, 0.01) var pose_time := 0.4
@onready var visual: MonsterVisual = $Visual
var _destroyed := false

func _ready() -> void:
	add_to_group("cave_hive_placeholders")
	visual.setup("the_monster")
	_standing_pose()

func _standing_pose() -> void:
	if visual.animator != null:
		visual.animator.seek(pose_time, true)
		visual.animator.pause()
	if visual.skeleton != null and visual.root_bone >= 0:
		visual.skeleton.set_bone_pose(visual.root_bone, visual.root_pose)
	visual.death_time = 0.0

func apply_snapshot(active: bool, health: float) -> void:
	visible = active
	collision_layer = 2 if active and health > 0.0 else 0
	var destroyed := health <= 0.0
	if destroyed != _destroyed:
		_destroyed = destroyed
		if destroyed:
			# Reuse the imported death pose and hold it; no AI or corpse simulation.
			visual.animate(1.5, false, false, true)
		else:
			_standing_pose()

func apply_weapon_damage(_amount: float) -> void:
	# Retain the weapon-hit contract so bullets stop at this collider.
	# Only the host's validated flame jet may damage the hive.
	pass

func apply_flame_damage(amount: float) -> void:
	get_parent().damage_hive(hive_index, amount)
