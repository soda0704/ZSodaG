extends SceneTree
func _initialize() -> void:
	var driver := Node.new()
	driver.name = "WiringNetworkTest"
	driver.set_script(load("res://tools/tests/breaker_wiring_multiplayer_regression.gd"))
	root.add_child.call_deferred(driver)
