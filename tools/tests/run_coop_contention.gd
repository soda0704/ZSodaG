extends SceneTree
func _initialize() -> void:
	var driver := Node.new()
	driver.name = "CoopContentionTest"
	driver.set_script(load("res://tools/tests/coop_contention_regression.gd"))
	root.add_child.call_deferred(driver)
