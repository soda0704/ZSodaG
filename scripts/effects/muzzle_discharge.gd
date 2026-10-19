extends Node3D
## Native, short-lived flame and low-opacity powder gas; no extra dynamic light.
func fire() -> void:
	$Flame.restart()
	$Gas.restart()
