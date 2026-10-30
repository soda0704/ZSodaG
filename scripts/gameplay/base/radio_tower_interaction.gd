class_name RadioTowerInteraction
extends StaticBody3D
@export_enum("note", "gate", "module", "socket") var role := "note"
@export_range(0.5,5.0) var interaction_distance := 2.6
@export_node_path("Node3D") var visual_path: NodePath
@export_node_path("CollisionShape3D") var gate_collision_path: NodePath
var state: BaseGameplayController
var _previous_unlocked := false
var _initialized := false
var _attempts := {}
var _previous_repaired := false

func _ready() -> void:
	_bind.call_deferred()

func _bind() -> void:
	state = get_tree().get_first_node_in_group("base_gameplay_controller") as BaseGameplayController
	if state != null:
		state.snapshot_changed.connect(refresh)
		refresh(state.get_snapshot())

func get_interaction_prompt() -> String:
	if state == null or state.day_index < 2: return ""
	match role:
		"note": return "Прочитать записку связиста"
		"gate": return "Ввести код ограждения" if not state.maintenance.get("radio_unlocked",false) else ""
		"module": return "Взять электромодуль вышки" if not state.maintenance.get("radio_module",false) and not state.maintenance.get("radio_repaired",false) else ""
		"socket": return "Связь восстановлена" if state.maintenance.get("radio_repaired",false) else "Заменить электромодуль" if state.maintenance.get("radio_module",false) else "Нужен запасной электромодуль"
	return ""

func can_use(peer: int, actor: Node) -> bool:
	var player := actor as GamePlayer
	if state == null or player == null or state.get_player_node(peer) != player or player.owner_peer_id != peer: return false
	if player.survival.dead or player.is_driving() or player.is_sleeping_in_bunk() or player.is_carrying_corpse() or player.is_climbing(): return false
	if player.global_position.distance_to(global_position) > interaction_distance: return false
	var query := PhysicsRayQueryParameters3D.create(player.camera.global_position,global_position,1,[player.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.collider == self

func begin_terminal_interaction() -> void:
	if state == null or get_interaction_prompt().is_empty(): return
	if role == "gate": $Keypad.open(self)
	else: request_action()

func request_action(code := "") -> void:
	if multiplayer.is_server(): _submit(multiplayer.get_unique_id(),code)
	else: _request.rpc_id(1,code)

@rpc("any_peer","call_remote","reliable",2)
func _request(code: String) -> void:
	if multiplayer.is_server(): _submit(multiplayer.get_remote_sender_id(),code)

func _submit(peer: int, code: String) -> void:
	if state == null: return
	var now := Time.get_ticks_msec()
	if now-int(_attempts.get(peer,-1000)) < 350: return
	_attempts[peer]=now
	var accepted := RadioTowerProgress.act(state,StringName(role),peer,self,code)
	if role == "gate":
		if peer==multiplayer.get_unique_id(): $Keypad.result(accepted)
		else: _result.rpc_id(peer,accepted)

@rpc("authority","call_remote","reliable",2)
func _result(accepted: bool) -> void:
	if role == "gate": $Keypad.result(accepted)

func network_interact(peer: int, _actor: Node) -> void:
	if role != "gate": _submit(peer,"")

func refresh(_snapshot: Dictionary) -> void:
	if role == "note":
		$Text.text = "ЗАПИСКА СВЯЗИСТА\nСвязь пропала: замените модуль\nв электрощите наверху радиовышки.\nКод ограждения: %s\nЗапасной модуль — уровень 3,\nу компьютера наблюдения." % state.maintenance.get("radio_pin","••••")
	elif role == "module":
		var collected: bool = state.maintenance.get("radio_module",false) or state.maintenance.get("radio_repaired",false)
		visible = not collected
		$CollisionShape3D.set_deferred("disabled",collected)
	elif role == "socket":
		var repaired: bool=state.maintenance.get("radio_repaired",false)
		if _initialized and not state.applying_initial_snapshot and repaired and not _previous_repaired:
			$Replacement/AnimationPlayer.play(&"replace")
			$Status.text="ЗАМЕНА МОДУЛЯ"
		elif not _initialized or state.applying_initial_snapshot:
			$Replacement/AnimationPlayer.play(&"replace")
			$Replacement/AnimationPlayer.seek(1.4 if repaired else 0.0,true)
			$Replacement/AnimationPlayer.pause()
			$Replacement/Extract.stop();$Replacement/Insert.stop()
			$Status.text="СВЯЗЬ АКТИВНА" if repaired else "СБОЙ МОДУЛЯ"
		_previous_repaired=repaired
	elif role == "gate":
		var unlocked: bool = state.maintenance.get("radio_unlocked",false)
		get_node(gate_collision_path).set_deferred("disabled",unlocked)
		if not _initialized or state.applying_initial_snapshot:
			$AnimationPlayer.play(&"open"); $AnimationPlayer.seek(1.0 if unlocked else 0.0,true); $AnimationPlayer.pause()
		elif unlocked and not _previous_unlocked: $AnimationPlayer.play(&"open")
		_previous_unlocked=unlocked
	_initialized=true
