extends SceneTree
func _initialize() -> void:
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING,"user://journal_network_%d.cfg" % OS.get_process_id())
	var driver := Node.new()
	driver.name = "JournalNetworkTest"
	driver.set_script(load("res://tools/tests/journal_pickup_multiplayer.gd"))
	root.add_child.call_deferred(driver)
