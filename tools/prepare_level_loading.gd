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
	plan = Builder.new().build(load(Builder.ROOT_PATH))
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
