extends SceneTree

const JOB = preload("res://scripts/network/level_load_job.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func construct_background(job: RefCounted, packed: PackedScene, result: Dictionary) -> void:
	result.node = await job.construct(packed, self)
	result.done = true

func run() -> void:
	var source := Node3D.new()
	var child := Node3D.new()
	source.add_child(child)
	child.owner = source
	var packed := PackedScene.new()
	check(packed.pack(source) == OK, "cancellation fixture packs")
	source.free()
	for iteration in 12:
		var job = JOB.new()
		var result := {"done": false, "node": null}
		construct_background(job, packed, result)
		check(job._pending_instances.size() == 1, "job owns the detached root while suspended %d" % iteration)
		var pending: WeakRef = weakref(job._pending_instances[0])
		job.cancel()
		job.cancel()
		await process_frame
		await process_frame
		check(result.done and result.node == null and pending.get_ref() == null, "cancel releases construction once and returns no stale node %d" % iteration)
		await job.finish_loading(self)
		check(not job.collisions_ready and await job.construct(packed, self) == null, "cancelled job cannot resume or start new construction %d" % iteration)
	var attached_job = JOB.new()
	var attached: Node = await attached_job.construct(packed, self)
	root.add_child(attached)
	attached_job.loaded_instance = attached
	attached_job.cancel()
	check(is_instance_valid(attached) and attached.is_inside_tree(), "cancellation leaves attached nodes to their scene owner")
	attached.queue_free()
	var detached_job = JOB.new()
	detached_job.loaded_instance = await detached_job.construct(packed, self)
	var detached: WeakRef = weakref(detached_job.loaded_instance)
	detached_job.cancel()
	check(detached.get_ref() == null, "cancellation releases a completed instance not yet attached")
	await process_frame
	print("LEVEL LOAD CANCELLATION CHECKS ", checks, " FAILURES ", failures)
	quit(1 if failures else 0)
