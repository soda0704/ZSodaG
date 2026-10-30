extends SceneTree
func _initialize() -> void:
	var test = load("res://tools/tests/monster_audio_multiplayer_regression.gd").new()
	test.name = "MonsterAudioRegression"
	root.add_child.call_deferred(test)
