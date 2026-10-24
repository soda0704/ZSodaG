extends RefCounted
## Construct an isolated scene off-tree. Only its owner may attach it on the main thread.
var _thread := Thread.new()

func instantiate(packed: PackedScene, tree: SceneTree) -> Node:
	var error := _thread.start(packed.instantiate)
	if error != OK:
		push_error("Could not start level construction: " + error_string(error))
		return null
	while _thread.is_alive():
		await tree.process_frame
	return _thread.wait_to_finish() as Node

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _thread.is_started():
		# Cancellation must join construction, including a scene change while IO
		# finishes. A result that never reached its owner is still off-tree.
		var abandoned := _thread.wait_to_finish() as Node
		if is_instance_valid(abandoned): abandoned.free()
