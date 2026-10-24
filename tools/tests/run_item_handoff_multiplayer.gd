extends SceneTree
func _initialize() -> void:
	var driver := Node.new()
	driver.name = "HandoffNetworkTest"
	driver.set_script(load("res://tools/tests/item_handoff_multiplayer_regression.gd"))
	root.add_child.call_deferred(driver)
