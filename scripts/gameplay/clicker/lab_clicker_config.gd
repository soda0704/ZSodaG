class_name LabClickerConfig
extends Resource

@export var title := "BIO SAMPLE SYNTHESIZER"
@export var resource_name_plural := "SAMPLES"
@export var base_click_power := 1.0
@export var upgrades: Array[ClickerUpgrade] = []
@export var max_owned := 999
@export var max_samples := 1.0e30
@export var click_sound: AudioStream
@export var purchase_sound: AudioStream
@export var error_sound: AudioStream


@export_group("Click rhythm")
@export_range(0.001, 1.0, 0.01) var activity_per_click := 0.09
@export_range(0.001, 1.0, 0.01) var activity_decay_per_second := 0.18
@export_range(0.01, 1.0, 0.01) var activity_threshold := 0.7
@export_range(1.0, 5.0, 0.1) var activity_multiplier := 1.5

@export_group("Rare bacterium")
@export_range(1.0, 600.0, 1.0) var bacteria_interval_min := 65.0
@export_range(1.0, 600.0, 1.0) var bacteria_interval_max := 115.0
@export_range(1.0, 60.0, 0.5) var bacteria_lifetime := 9.0
@export_range(0.0, 60.0, 0.5) var bacteria_clicks_reward := 8.0
@export_range(0.0, 60.0, 0.5) var bacteria_seconds_reward := 5.0
