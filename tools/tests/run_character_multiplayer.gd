extends SceneTree
func _initialize() -> void:
	var driver := Node.new()
	driver.name = "CharacterNetworkTest"
	driver.set_script(load("res://tools/tests/character_multiplayer_regression.gd"))
	if OS.get_cmdline_user_args().has("--presentation-clock"):
		driver.set_script(load("res://tools/tests/first_person_network_pacing_regression.gd"))
	root.add_child.call_deferred(driver)
