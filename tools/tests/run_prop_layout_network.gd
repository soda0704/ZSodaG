extends SceneTree
func _initialize():
 var driver = Node.new()
 driver.name = "PropNetworkReview"
 driver.set_script(load("res://tools/tests/prop_layout_network_review.gd"))
 root.add_child.call_deferred(driver)
