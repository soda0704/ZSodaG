class_name ClickerUpgrade
extends Resource

enum Effect { CLICK_POWER, PASSIVE_INCOME }
@export var id: StringName
@export var title: String
@export_multiline var description: String
@export var icon: Texture2D
@export_range(1.0, 1000000.0, 1.0, "or_greater") var base_cost := 15.0
@export_range(1.0, 3.0, 0.01) var cost_multiplier := 1.15
@export var effect_type: Effect = Effect.CLICK_POWER
@export_range(0.0, 1000000.0, 1.0, "or_greater") var effect_value := 1.0
