extends SceneTree
func _initialize():
	var test=load("res://tools/tests/radio_tower_multiplayer_regression.gd").new()
	test.name="RadioRegression"
	root.add_child.call_deferred(test)
