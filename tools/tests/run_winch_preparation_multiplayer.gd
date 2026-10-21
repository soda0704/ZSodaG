extends SceneTree
func _initialize() -> void:
	var driver := Node.new()
	driver.name = "WinchPreparationNetworkTest"
	driver.set_script(load("res://tools/tests/winch_preparation_multiplayer_regression.gd"))
	root.add_child.call_deferred(driver)
