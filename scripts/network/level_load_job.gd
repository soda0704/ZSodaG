extends RefCounted
## Resource IO stays asynchronous; rendering nodes are constructed on the owner thread.

func instantiate(packed: PackedScene, _tree: SceneTree) -> Node:
	# Off-tree does not make rendering-node construction thread-safe. The worker
	# raced the live renderer during arrival (invalid uniform sets), even though
	# gameplay assertions still passed.
	return packed.instantiate()
