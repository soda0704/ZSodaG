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
