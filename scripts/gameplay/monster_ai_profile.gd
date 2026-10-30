class_name MonsterAIProfile
extends Resource

enum Behavior { PURSUER, SKIRMISHER, TERRITORIAL }
@export_group("Behavior")
@export var behavior: Behavior = Behavior.PURSUER
@export_range(1.0, 2000.0) var max_health := 160.0
@export_range(0.1, 12.0) var chase_speed := 2.1
@export_range(0.0, 5.0) var patrol_speed := 0.65
@export_range(0.1, 20.0) var turn_speed := 6.0
@export_range(0.0, 50.0) var patrol_radius := 6.0
@export_range(0.1, 30.0) var patrol_interval_min := 5.0
@export_range(0.1, 30.0) var patrol_interval_max := 10.0
@export_range(1.0, 100.0) var territory_radius := 24.0
@export_group("Perception")
@export var sight_enabled := true
@export var hearing_enabled := true
@export_range(1.0, 100.0) var sight_distance := 24.0
@export_range(10.0, 360.0) var field_of_view := 116.0
@export_range(0.0, 10.0) var close_awareness_distance := 3.0
@export_range(0.0, 3.0) var crouched_awareness_distance := 0.7
@export_range(0.05, 2.0) var sight_interval := 0.15
@export_range(0.1, 60.0) var sight_memory := 18.0
@export_range(0.1, 60.0) var hearing_memory := 8.0
@export_range(0.0, 3.0) var hearing_multiplier := 1.0
@export_range(0.1, 20.0) var vertical_awareness := 4.0
@export_range(0.1, 1.0) var occluded_hearing_multiplier := 0.55
@export_group("Combat")
@export_range(0.1, 5.0) var attack_distance := 1.65
@export_range(0.1, 5.0) var attack_reach := 2.0
@export_range(0.05, 5.0) var attack_windup := 0.65
@export_range(0.1, 10.0) var attack_cooldown := 1.9
@export_range(0.0, 200.0) var attack_damage := 20.0
@export_range(0.0, 3.0) var retreat_duration := 0.65
@export_range(0.0, 8.0) var retreat_distance := 2.3
@export_group("Navigation")
@export_range(0.05, 3.0) var path_update_interval := 0.3
@export_range(0.05, 5.0) var stop_distance := 1.4
@export_range(0.05, 3.0) var patrol_stop_distance := 0.7
@export_range(0.1, 5.0) var navigation_projection_distance := 2.0
@export_range(0.5, 10.0) var stuck_timeout := 2.0
@export_group("Investigation")
@export_range(0.5, 15.0) var search_duration := 4.0
@export_range(0.5, 10.0) var search_radius := 3.0

@export_group("Stealth and detection")
## Continuous visible exposure needed to identify a new player. Zero keeps instant recognition.
@export_range(0.0, 5.0) var sight_confirmation_time := 0.0
## Crouching can reduce the sight radius, but never lets the player hide in plain sight at contact.
@export_range(0.1, 1.0) var crouched_sight_multiplier := 0.8
## Also test the upper torso; a blocked head alone does not mean the whole player is hidden.
@export var sight_body_sample := true
@export_flags_3d_physics var perception_collision_mask := 1
## Only switch away from a visible current target when another player is substantially closer.
@export_range(0.1, 1.0) var target_switch_ratio := 0.65

@export_group("Attack rules")
## Disable attacks for a stalking/chase-only creature without disabling perception or movement.
@export var attacks_enabled := true
@export_range(10.0, 360.0) var attack_arc := 140.0
## A visible recovery interval after contact/miss, independent of the next attack cooldown.
@export_range(0.0, 5.0) var attack_recovery := 0.2
## Optional smooth acceleration. Zero preserves immediate authored movement speed.
@export_range(0.0, 40.0) var acceleration := 0.0
@export var weapon_damage_enabled := true
@export var environment_damage_enabled := true

@export_group("Search and recovery")
@export var return_home_after_search := true
## Brief listening pauses while searching; prevents constant spinning at an obstructed goal.
@export_range(0.0, 5.0) var search_pause := 0.4
@export_range(0.0, 2.0) var minimum_progress_distance := 0.2
@export_range(1, 10) var maximum_path_retries := 3
@export_range(0.1, 30.0) var unreachable_target_cooldown := 3.0

@export_group("Navigation agent")
@export_flags_3d_navigation var navigation_layers := 1
@export_range(0.05, 2.0) var path_desired_distance := 0.35
## Subtracted from baked path Y so the agent follows at its authored foot pivot.
@export_range(-3.0, 3.0, 0.05) var path_height_offset := 0.0
## Match the authored collision capsule, not the visual model's height or scale.
@export_range(0.05, 3.0) var avoidance_radius := 0.4
## RVO uses the native NavigationAgent3D. Enable only where crowd avoidance is needed.
@export var avoidance_enabled := false
@export_range(0.1, 20.0) var neighbor_distance := 5.0
@export_range(1, 32) var max_neighbors := 8
