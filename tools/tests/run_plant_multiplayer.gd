extends SceneTree
func _initialize() -> void:
	var driver := Node.new()
	driver.name = "PlantNetworkTest"
	driver.set_script(load("res://tools/tests/plant_watering_multiplayer_regression.gd"))
	root.add_child.call_deferred(driver)
