extends Control

func _ready() -> void:
	$AnimationPlayer.animation_finished.connect(func(_name): queue_free())

func show_amount(amount: float) -> void:
	$Number.text = "+" + LabClicker.format_number(amount)
