extends SceneTree
func _initialize() -> void:
 var driver := Node.new()
 driver.name = "FlashlightNetworkTest"
 driver.set_script(load("res://tools/tests/flashlight_multiplayer_regression.gd"))
 root.add_child.call_deferred(driver)
