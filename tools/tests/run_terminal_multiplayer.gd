extends SceneTree
func _initialize() -> void:
	var driver := Node.new()
	driver.name = "TerminalNetworkTest"
	driver.set_script(load("res://tools/tests/day_two_terminal_multiplayer_regression.gd"))
	root.add_child.call_deferred(driver)
