class_name AudioMixController
extends Node

const VOLUME_BUSES := {"EffectsVolume": "Effects", "WeaponsVolume": "Weapons", "VehiclesVolume": "Vehicles", "MachineryVolume": "Machinery", "AmbienceVolume": "Ambience", "BreathingVolume": "Breathing"}
@export var indoor_reverb_wet := 0.12
@export var outdoor_cutoff_hz := 10000.0
@export var indoor_cutoff_hz := 18000.0
@export var acoustic_transition_seconds := 0.8
var room_amount := 0.5
var _room_blend := 0.0

func _ready() -> void:
	get_tree().node_added.connect(_route_default)

func _route_default(node: Node) -> void:
	if node is AudioStreamPlayer3D:
		_route_id.call_deferred(node.get_instance_id())

func _route_id(id: int) -> void:
	var node := instance_from_id(id)
	if node is AudioStreamPlayer3D and node.bus == &"Master":
		node.bus = &"Effects"

func apply_settings(data: Dictionary) -> void:
	for key in VOLUME_BUSES:
		var bus := AudioServer.get_bus_index(VOLUME_BUSES[key])
		if bus < 0:
			continue
		var percent := clampf(float(data.get(key, 100.0)), 0.0, 100.0)
		AudioServer.set_bus_mute(bus, percent <= 0.0)
		AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(percent / 100.0, 0.0001)))
	room_amount = clampf(float(data.get("RoomReverb", 50.0)) / 100.0, 0.0, 1.0)

func update_acoustics(delta: float, indoor: float) -> void:
	_room_blend = lerpf(_room_blend, indoor, 1.0 - exp(-delta / maxf(acoustic_transition_seconds, 0.01)))
	var bus := AudioServer.get_bus_index("World")
	if bus >= 0:
		var reverb := AudioServer.get_bus_effect(bus, 0) as AudioEffectReverb
		var filter := AudioServer.get_bus_effect(bus, 1) as AudioEffectLowPassFilter
		if reverb != null:
			reverb.wet = indoor_reverb_wet * room_amount * _room_blend
		if filter != null:
			filter.cutoff_hz = lerpf(outdoor_cutoff_hz, indoor_cutoff_hz, _room_blend)

func _process(delta: float) -> void:
	var acoustics := get_tree().get_first_node_in_group("exterior_acoustics") as ExteriorAcoustics
	update_acoustics(delta, 1.0 - acoustics.outside_blend if acoustics != null else 0.0)
