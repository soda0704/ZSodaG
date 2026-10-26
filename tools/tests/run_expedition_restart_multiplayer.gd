extends SceneTree
func _initialize() -> void:
	var driver := Node.new()
	driver.name = "ExpeditionRestartTest"
	driver.set_script(load("res://tools/tests/expedition_restart_multiplayer_regression.gd"))
	root.add_child.call_deferred(driver)
