extends SceneTree

const JOB = preload("res://scripts/network/level_load_job.gd")
const PATH := "res://scenes/levels/base_blockout_v03.tscn"
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func request_background(job: RefCounted, result: Dictionary) -> void:
	result.packed = await job.request_scene(PATH, self)
	result.done = true

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Threaded resource request test requires the real renderer")
		quit(1)
		return
	var job = JOB.new()
	var result := {"done": false, "packed": null}
	request_background(job, result)
	var was_pending: bool = not result.done
	print("RESOURCE REQUEST PENDING AT CANCEL ", was_pending)
	job.cancel()
	var deadline := Time.get_ticks_msec() + 60000
	while not result.done and Time.get_ticks_msec() < deadline:
		await process_frame
	check(result.done, "native request completes after cancellation")
	if was_pending:
		check(result.packed == null, "cancelled native result is consumed without publishing a scene")
	else:
		check(result.packed is PackedScene, "completed cache hit remains owned by its caller")
	var next = JOB.new()
	var packed: PackedScene = await next.request_scene(PATH, self)
	check(packed != null and packed.can_instantiate(), "same scene can be requested again after cancellation")
	print("LEVEL RESOURCE REQUEST FAILURES ", failures)
	quit(1 if failures else 0)
