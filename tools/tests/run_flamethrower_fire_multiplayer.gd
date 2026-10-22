extends SceneTree
func _initialize() -> void:
	var driver:=Node.new();driver.name="FlamethrowerFireNetworkTest"
	driver.set_script(load("res://tools/tests/flamethrower_fire_multiplayer_regression.gd"))
	root.add_child.call_deferred(driver)
