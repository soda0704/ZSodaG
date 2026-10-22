extends SceneTree
func _initialize() -> void:
	var driver := Node.new()
	driver.name = "CaveHivesNetworkTest"
	driver.set_script(load("res://tools/tests/cave_hives_multiplayer_regression.gd"))
	root.add_child.call_deferred(driver)
