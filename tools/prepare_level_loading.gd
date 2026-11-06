extends SceneTree
const Builder = preload("res://scripts/network/level_load_plan.gd")


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var plan = load(Builder.PLAN_PATH) if ResourceLoader.exists(Builder.PLAN_PATH) else null
	if Builder.current(plan):
		print("LEVEL LOAD PLAN current")
		quit(0)
		return
	# The old plan can cache its nested PackedScenes. Refresh scene files from
	# leaves to root, while retaining canonical Script resources/class identity.
	if plan != null:
		var paths: Array = plan.get_meta("source_hashes", {}).keys()
		paths.reverse()
		for path in paths:
			if str(path).ends_with(".tscn") and ResourceLoader.exists(path):
				ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE)
	plan = Builder.new().build(ResourceLoader.load(Builder.ROOT_PATH, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE))
	if plan == null:
		quit(1)
		return
	var previous_uid = (
		ResourceLoader.get_resource_uid(Builder.PLAN_PATH)
		if ResourceLoader.exists(Builder.PLAN_PATH)
		else -1
	)
	var error = ResourceSaver.save(plan, Builder.PLAN_PATH)
	if error == OK and previous_uid != -1:
		ResourceSaver.set_uid(Builder.PLAN_PATH, previous_uid)
	print("LEVEL LOAD PLAN saved: ", error, " scopes ", plan.get_meta("skeletons").size())
	quit(0 if error == OK else 1)
