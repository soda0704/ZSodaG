extends SceneTree
func _initialize() -> void:
	var driver := Node.new()
	driver.name="MedicalNetworkTest"
	driver.set_script(load("res://tools/tests/medical_corpse_multiplayer_regression.gd"))
	root.add_child.call_deferred(driver)
