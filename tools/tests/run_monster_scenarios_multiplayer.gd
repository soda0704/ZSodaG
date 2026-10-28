extends SceneTree


func _initialize() -> void:
	var driver := Node.new()
	driver.name = "MonsterScenarioTest"
	driver.set_script(load("res://tools/tests/monster_scenario_multiplayer_regression.gd"))
	root.add_child.call_deferred(driver)
