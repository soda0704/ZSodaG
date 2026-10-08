extends SceneTree
func _initialize() -> void:
	var driver := Node.new()
	driver.name = "CharacterNetworkTest"
	driver.set_script(load("res://tools/tests/character_multiplayer_regression.gd"))
	root.add_child.call_deferred(driver)
