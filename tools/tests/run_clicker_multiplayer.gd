extends SceneTree
func _initialize() -> void:
	var driver := Node.new()
	driver.name = "ClickerNetworkTest"
	driver.set_script(load("res://tools/tests/lab_clicker_multiplayer_regression.gd"))
	root.add_child.call_deferred(driver)
