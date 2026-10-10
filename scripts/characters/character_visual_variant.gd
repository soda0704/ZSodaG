class_name CharacterVisualVariant
extends Resource

@export_range(0, 1) var variant_id := 0
@export var display_name := ""
@export var body_scene: PackedScene
@export var first_person_scene: PackedScene
@export var ragdoll_scene: PackedScene
@export var retarget_bone_map: BoneMap
@export_range(0.5, 2.0) var locomotion_rate := 1.0
@export_range(0.0, 90.0) var idle_turn_limit_degrees := 35.0
@export_range(1.0, 20.0) var body_turn_speed := 7.0
@export_range(0.0, 1.0) var inertia_strength := 0.7

@export_group("Animation stride, metres per second")
@export_range(0.1,10.0) var forward_walk_stride_speed := 2.72
@export_range(0.1,10.0) var other_walk_stride_speed := 1.79
@export_range(0.1,10.0) var run_stride_speed := 3.186
@export_range(0.1,10.0) var crouch_stride_speed := 1.105
