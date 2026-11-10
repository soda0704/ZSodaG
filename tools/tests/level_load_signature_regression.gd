extends SceneTree
const Plan = preload("res://scripts/network/level_load_plan.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func fixture(label: String, nodes: String) -> PackedScene:
	var path := "user://load_signature_%d_%s.tscn" % [OS.get_process_id(), label]
	FileAccess.open(path, FileAccess.WRITE).store_string("[gd_scene format=3]\n[node name=\"Root\" type=\"Node3D\"]\n" + nodes)
	var packed := load(path) as PackedScene
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return packed

func run() -> void:
	var left := "[node name=\"Left\" type=\"Node3D\" parent=\".\"]\n"
	var right := "[node name=\"Right\" type=\"Node3D\" parent=\".\"]\n"
	var a := "[node name=\"A\" type=\"Node3D\" parent=\"Left\"]\n"
	var b := "[node name=\"B\" type=\"Node3D\" parent=\"Left\"]\n"
	var interleaved := fixture("interleaved", left + a + right + b)
	var grouped := fixture("grouped", left + a + b + right)
	var reordered := fixture("reordered", left + b + a + right)
	var moved := fixture("moved", left + a + "position = Vector3(1, 0, 0)\n" + b + right)
	var selected := PackedStringArray()
	check(Plan.signature(interleaved, selected) == Plan.signature(grouped, selected), "export row grouping preserves the same node tree signature")
	check(Plan.signature(grouped, selected) != Plan.signature(reordered, selected), "real sibling reordering still invalidates the cached scene")
	check(Plan.signature(grouped, selected) != Plan.signature(moved, selected), "a changed transform still invalidates the cached scene")
	print("LEVEL LOAD SIGNATURE CHECKS ", checks, " FAILURES ", failures)
	quit(1 if failures else 0)
