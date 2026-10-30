extends Control
## A state-change notice, never replayed while loading an existing snapshot.
var _state: BaseGameplayController
var _bind_elapsed := .25
var _powered := false
@onready var player: GamePlayer = get_parent().get_parent().get_parent()

func _ready() -> void:
	$AnimationPlayer.animation_finished.connect(func(_clip): hide())

func _process(delta: float) -> void:
	_bind_elapsed+=delta
	if _bind_elapsed>=.25:
		_bind_elapsed=0
		var next:=get_tree().get_first_node_in_group("base_gameplay_controller") as BaseGameplayController
		if next!=_state:
			if is_instance_valid(_state): _state.power_state_changed.disconnect(_power_changed)
			_state=next;hide()
			if _state!=null:
				_powered=_state.main_breaker_on
				$Panel/Icon.animation=&"on" if _powered else &"off"
				$Panel/Icon.frame=20
				_state.power_state_changed.connect(_power_changed)

func _power_changed(powered: bool) -> void:
	if powered==_powered: return
	_powered=powered
	if not player.is_local_player(): return
	var phase:int=$Panel/Icon.frame if $Panel/Icon.animation==&"on" else 20-$Panel/Icon.frame
	var was_visible:=visible
	$Panel/Title.text="Питание включено" if powered else "Питание отключено"
	$Panel/Icon.play(&"on" if powered else &"off")
	$Panel/Icon.frame=phase if powered else 20-phase
	$AnimationPlayer.stop();$AnimationPlayer.play(&"notice");$AnimationPlayer.advance(0)
	if was_visible: $AnimationPlayer.seek(.16,true)
	show()
