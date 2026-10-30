class_name MonsterAudioProfile
extends Resource
## Presentation only: these values never change hearing, attacks or other gameplay rules.
@export_group("Voice and actions")
@export var ambient: Array[AudioStream] = []
@export var alert: Array[AudioStream] = []
@export var search: Array[AudioStream] = []
@export var windup: Array[AudioStream] = []
@export var strike: Array[AudioStream] = []
@export var miss: Array[AudioStream] = []
@export var voice_volume_db := -17.0
@export var cue_volume_db := -13.0
@export var pitch_range := Vector2(0.96, 1.04)
@export var idle_pause := Vector2(6.0, 12.0)
@export var chase_pause := Vector2(4.0, 7.0)
@export_range(0.0, 20.0) var alert_cooldown := 5.0
@export_range(0.1, 5.0) var loss_confirmation := 0.65
@export_range(0.0, 20.0) var search_cooldown := 5.0
@export_group("Feet")
@export var floor_steps: Array[AudioStream] = []
@export var metal_steps: Array[AudioStream] = []
@export var snow_steps: Array[AudioStream] = []
@export var step_volume_db := -22.0
## Normalized touchdown phases in the authored walk cycle; simultaneous feet share a contact.
@export var contact_phases := PackedFloat32Array([0.0, 0.5])
@export var animation_contacts := true
## Old models without named locomotion clips retain a distance-based contact cadence.
@export_range(0.1, 3.0) var fallback_stride := 0.95
@export_range(0.02, 0.3) var minimum_step_interval := 0.035
@export_group("Spatial mix")
@export_range(1.0, 80.0) var voice_distance := 30.0
@export_range(1.0, 80.0) var cue_distance := 26.0
@export_range(1.0, 50.0) var step_distance := 17.0
@export_range(0.1, 10.0) var unit_size := 3.0
@export_range(0.1, 1.0) var occlusion_interval := 0.2
@export_range(0.01, 1.0) var occlusion_fade := 0.15
@export var wall_loss_db := -14.0
@export var floor_loss_db := -34.0
@export_range(3.0, 20.0) var floor_separation := 7.0
