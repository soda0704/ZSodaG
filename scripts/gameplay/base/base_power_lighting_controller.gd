class_name BasePowerLightingController
extends Node

signal lighting_state_changed(is_standard_powered: bool)

@export var gameplay_controller_path := NodePath("../BaseGameplayController")
@export var standard_lighting_path := NodePath(
	"../Floor_0_Base_Blockout/Power_State_Lighting_Blockout/"
	+ "Standard_Lighting_Blockout"
)
@export var emergency_lighting_path := NodePath(
	"../Floor_0_Base_Blockout/Power_State_Lighting_Blockout/"
	+ "Day1_Emergency_Lighting_Blockout"
)

var is_standard_powered: bool = false
var _gameplay_controller: BaseGameplayController
var _standard_lighting: Node3D
var _emergency_lighting: Node3D
var _fault_time: float = 0.0
var _containment_lights: Dictionary = {}
var _lamp_materials: Dictionary = {}
var _last_level_factor := -1.0
var _last_standard_visible := false
var _last_emergency_visible := false


func _ready() -> void:
	_gameplay_controller = get_node_or_null(
		gameplay_controller_path
	) as BaseGameplayController
	_standard_lighting = get_node_or_null(standard_lighting_path) as Node3D
	_emergency_lighting = get_node_or_null(emergency_lighting_path) as Node3D

	if _standard_lighting == null:
		push_warning("Base standard lighting layer was not found")
	if _emergency_lighting == null:
		push_warning("Base emergency lighting layer was not found")
	if _gameplay_controller == null:
		push_warning("BasePowerLightingController could not find gameplay state")
		apply_power_state(false, true)
		return

	if not _gameplay_controller.power_state_changed.is_connected(
		_on_power_state_changed
	):
		_gameplay_controller.power_state_changed.connect(
			_on_power_state_changed
		)
	apply_power_state(_gameplay_controller.main_breaker_on, true)
	var level := get_parent().get_node_or_null("Floor_Minus3_Biocontainment_Blockout")
	if level != null:
		for light: Light3D in level.find_children("*", "Light3D", true, false):
			light.shadow_enabled = true
			_containment_lights[light] = light.light_energy
		for lamp in level.find_children("*", "CSGPrimitive3D", true, false):
			if "light" not in str(lamp.get_path()).to_lower():
				continue
			var material = lamp.material
			if material is StandardMaterial3D and material.emission_enabled:
				var copy := material.duplicate() as StandardMaterial3D
				lamp.material = copy
				_lamp_materials[copy] = {"energy": copy.emission_energy_multiplier, "albedo": copy.albedo_color}

func _process(delta: float) -> void:
	if _gameplay_controller == null:
		return
	_fault_time += delta
	var faulty: bool = _gameplay_controller.containment.get("fault", false)
	var outage_alarm := not is_standard_powered and bool(_gameplay_controller.maintenance.get("alarm", false))
	# Slow, low-contrast power instability rather than a rapid strobe.
	var factor := (0.06 if fmod(_fault_time, 1.8) < 0.65 else 1.0) if faulty else 1.0
	var level_factor := factor if is_standard_powered else 0.06
	var standard_visible := is_standard_powered and (not faulty or factor > 0.52)
	# Wiring/fuel outages use the emergency circuit, not the disabled mains.
	var emergency_visible := not is_standard_powered and (not outage_alarm or fmod(_fault_time, 1.8) >= 0.65)
	if is_equal_approx(level_factor, _last_level_factor) and standard_visible == _last_standard_visible and emergency_visible == _last_emergency_visible:
		return
	_last_level_factor = level_factor
	_last_standard_visible = standard_visible
	_last_emergency_visible = emergency_visible
	if _standard_lighting != null:
		_standard_lighting.visible = standard_visible
	if _emergency_lighting != null:
		_emergency_lighting.visible = emergency_visible
	for light: Light3D in _containment_lights:
		if is_instance_valid(light):
			light.light_energy = _containment_lights[light] * level_factor
	for material: StandardMaterial3D in _lamp_materials:
		material.emission_energy_multiplier = _lamp_materials[material].energy * level_factor
		material.albedo_color = _lamp_materials[material].albedo * Color(level_factor, level_factor, level_factor, 1)


func apply_power_state(is_powered: bool, force: bool = false) -> void:
	_last_level_factor = -1.0
	var changed := is_standard_powered != is_powered
	is_standard_powered = is_powered
	if _standard_lighting != null:
		_standard_lighting.visible = is_standard_powered
	if _emergency_lighting != null:
		_emergency_lighting.visible = not is_standard_powered
	if changed or force:
		lighting_state_changed.emit(is_standard_powered)


func _on_power_state_changed(is_powered: bool) -> void:
	apply_power_state(is_powered)
