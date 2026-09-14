extends SceneTree

class EncounterStub extends Node:
	var candidate := Node3D.new()
	func closest_player(_point: Vector3) -> Node3D:
		return candidate

class SightProbe extends "res://scripts/gameplay/hostile_monster.gd":
	var checks := 0
	func _ready() -> void:
		set_physics_process(false)
	func _can_see(_target: Node3D) -> bool:
		checks += 1
		return false

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var encounter := EncounterStub.new()
	root.add_child(encounter)
	encounter.add_child(encounter.candidate)
	var probe := SightProbe.new()
	probe.encounter = encounter
	root.add_child(probe)
	for tick in 60:
		probe._find_target(1.0 / 60.0)
	print("SIGHT_BUDGET: ", probe.checks, " sight checks / 60 physics ticks")
	var passed := probe.checks >= 6 and probe.checks <= 7
	probe.free()
	encounter.free()
	quit(0 if passed else 1)
