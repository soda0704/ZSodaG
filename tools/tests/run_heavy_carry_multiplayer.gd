extends SceneTree
func _initialize() -> void:
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, "user://heavy_network_%d.cfg" % OS.get_process_id())
	var driver:=Node.new()
	driver.name="HeavyCarryNetworkTest"
	driver.set_script(load("res://tools/tests/heavy_carry_multiplayer_regression.gd"))
	root.add_child.call_deferred(driver)
