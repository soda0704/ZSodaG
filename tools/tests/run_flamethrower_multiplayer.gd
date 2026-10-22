extends SceneTree
func _initialize() -> void:
	var driver:=Node.new();driver.name="FlamethrowerNetworkTest"
	driver.set_script(load("res://tools/tests/flamethrower_multiplayer_regression.gd"))
	root.add_child.call_deferred(driver)
