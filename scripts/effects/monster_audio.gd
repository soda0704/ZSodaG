extends AudioStreamPlayer3D
## Presentation only. Host publishes action cues; local feet follow the animation clock.
signal sound_played(kind: StringName, sequence: int)
signal footstep_played(surface: StringName, phase: float)
enum Cue { ALERT, SEARCH, WINDUP, STRIKE, MISS, CANCEL }
const CUE_NAMES := [&"alert", &"search", &"windup", &"strike", &"miss", &"cancel"]
const PRIORITIES := [1, 0, 3, 4, 4, 5]
@export var profile: MonsterAudioProfile
## Compatibility for older/replacement scenes without an assigned audio profile.
@export var voices: Array[AudioStream] = []
@export var voice_override: AudioStream
@export var initial_delay_range := Vector2(0.15, 4.5)
@export var tail_volume_db := -7.0
var countdown := 0.0
var voice_pitch := 1.0
var occlusion_blend := 0.0
var floor_blend := 0.0
var occlusion_probes := 0
@onready var _voice_muffled: AudioStreamPlayer3D = $MuffledVoice
@onready var _feet: AudioStreamPlayer3D = $Movement
@onready var _feet_muffled: AudioStreamPlayer3D = $MuffledMovement
@onready var _cue: AudioStreamPlayer3D = $Action
@onready var _cue_muffled: AudioStreamPlayer3D = $MuffledAction
var _actor: Node3D
var _rng := RandomNumberGenerator.new()
var _clock := 0.0
var _probe_left := 0.0
var _occlusion_target := 0.0
var _floor_target := 0.0
var _listener: Camera3D
var _listener_position := Vector3.INF
var _was_audible := false
var _position_before := Vector3.ZERO
var _previous_phase := -1.0
var _previous_clip := &""
var _distance := 0.0
var _step_left := 0.0
var _feet_idle := 0.0
var _surface_left := 0.0
var _surface := &"floor"
var _supported := false
var _loss_left := -1.0
var _cancelled_finish := false
var _serial := 0
var _received := 0
var _pending: Array[Dictionary] = []
var _cooldowns := {}
var _last_sample := {}
var _cue_kind := -1
var _cue_priority := -1
var _silent := true

func _ready() -> void:
	_actor = get_parent() as Node3D
	_rng.randomize()
	if profile == null:
		profile = MonsterAudioProfile.new()
		if str(_actor.get("model_id")) == "the_monster": profile.voice_volume_db = tail_volume_db
	countdown = _rng.randf_range(initial_delay_range.x, initial_delay_range.y)
	voice_pitch = _rng.randf_range(profile.pitch_range.x, profile.pitch_range.y)
	_probe_left = _rng.randf_range(0.0, profile.occlusion_interval)
	_position_before = _actor.global_position
	process_physics_priority = 10
	for player in [self, _voice_muffled, _cue, _cue_muffled, _feet, _feet_muffled]:
		player.unit_size = profile.unit_size
		player.volume_db = -80.0
	max_distance = profile.voice_distance
	_voice_muffled.max_distance = max_distance
	for player in [_cue, _cue_muffled]: player.max_distance = profile.cue_distance
	for player in [_feet, _feet_muffled]:
		player.max_distance = profile.step_distance
		player.position.y = -position.y + 0.05
	if _actor.has_signal("target_spotted"): _actor.target_spotted.connect(_on_spotted)
	if _actor.has_signal("target_lost"): _actor.target_lost.connect(_on_lost)
	if _actor.has_signal("attack_started"): _actor.attack_started.connect(_on_attack_started)
	if _actor.has_signal("attack_cancelled"): _actor.attack_cancelled.connect(_on_attack_cancelled)
	if _actor.has_signal("attack_finished"): _actor.attack_finished.connect(_on_attack_finished)

func _active() -> bool:
	return (is_instance_valid(_actor) and _actor.is_visible_in_tree()
		and float(_actor.get("health")) > 0.0 and _actor.get("ai_enabled") != false
		and not (_actor.has_method("is_encounter_resolved") and _actor.is_encounter_resolved()))

func _physics_process(delta: float) -> void:
	_clock += delta
	_step_left = maxf(0.0, _step_left - delta)
	_surface_left -= delta
	countdown -= delta
	var movement := _actor.global_position - _position_before
	_position_before = _actor.global_position
	if not _active():
		_stop_all()
		_loss_left = -1.0
		return
	_listener = get_viewport().get_camera_3d()
	var limit := maxf(profile.voice_distance, maxf(profile.cue_distance, profile.step_distance))
	var audible := _listener != null and _listener.global_position.distance_to(global_position) < limit
	_update_loss(delta)
	if not audible:
		_stop_all()
		_was_audible = false
		if countdown <= 0.0: countdown = _next_pause()
		return
	var reset := not _was_audible or _listener_position.distance_to(_listener.global_position) > 4.0
	_listener_position = _listener.global_position
	_was_audible = true
	_probe_left -= delta
	if reset or _probe_left <= 0.0:
		_probe_left = profile.occlusion_interval
		_probe_occlusion(_listener)
	if reset:
		occlusion_blend = _occlusion_target
		floor_blend = _floor_target
	else:
		var blend := 1.0 - exp(-delta / maxf(profile.occlusion_fade,0.01))
		occlusion_blend = lerpf(occlusion_blend, _occlusion_target, blend)
		floor_blend = lerpf(floor_blend, _floor_target, blend)
	_mix_pairs()
	_consume_events()
	_update_feet(movement, delta)
	if countdown <= 0.0:
		countdown = _next_pause()
		if not playing and not _cue.playing and _loss_left < 0.0:
			var sample := voice_override if voice_override != null else _sample(profile.ambient, &"ambient")
			if sample == null:
				var index := 0 if str(_actor.get("model_id")) == "the_monster" else 1 if str(_actor.get("model_id")) == "slasher" else 2
				if voices.size() > index: sample = voices[index]
			if sample != null:
				_play_pair(self, _voice_muffled, sample, voice_pitch * _rng.randf_range(.98, 1.02))

func _next_pause() -> float:
	var interval := profile.chase_pause if _actor.get("_sees_target") == true else profile.idle_pause
	return _rng.randf_range(interval.x, interval.y)

func _probe_occlusion(camera: Camera3D) -> void:
	occlusion_probes += 1
	var excluded: Array[RID] = []
	if _actor is CollisionObject3D: excluded.append(_actor.get_rid())
	var parent: Node = camera
	while parent != null:
		if parent is CollisionObject3D: excluded.append(parent.get_rid())
		parent = parent.get_parent()
	var side := camera.global_basis.x.normalized() * 0.24
	var blocked := 0
	for offset in [Vector3.ZERO, side, -side]:
		var query := PhysicsRayQueryParameters3D.create(camera.global_position + offset, global_position, 1, excluded)
		if not get_world_3d().direct_space_state.intersect_ray(query).is_empty(): blocked += 1
	_occlusion_target = float(blocked) / 3.0
	_floor_target = 1.0 if blocked > 0 and absf(camera.global_position.y - global_position.y) > profile.floor_separation else 0.0

func _mix_pairs() -> void:
	var extra := db_to_linear(profile.floor_loss_db * floor_blend)
	var dry := (1.0 - occlusion_blend) * extra
	var muffled := occlusion_blend * db_to_linear(profile.wall_loss_db) * extra
	for pair in [[self, _voice_muffled, profile.voice_volume_db], [_feet, _feet_muffled, profile.step_volume_db], [_cue, _cue_muffled, profile.cue_volume_db]]:
		pair[0].volume_db = float(pair[2]) + linear_to_db(maxf(dry, 0.00001))
		pair[1].volume_db = float(pair[2]) + linear_to_db(maxf(muffled, 0.00001))

func _sample(clips: Array[AudioStream], key: StringName) -> AudioStream:
	if clips.is_empty(): return null
	var index := _rng.randi_range(0, clips.size() - 1)
	if clips.size() > 1 and index == int(_last_sample.get(key, -1)): index = (index + 1) % clips.size()
	_last_sample[key] = index
	return clips[index]

func _play_pair(dry: AudioStreamPlayer3D, muffled: AudioStreamPlayer3D, sample: AudioStream, pitch: float) -> void:
	_silent = false
	dry.stream = sample; muffled.stream = sample
	dry.pitch_scale = pitch; muffled.pitch_scale = pitch
	dry.play(); muffled.play()

func _clips(kind: int) -> Array[AudioStream]:
	match kind:
		Cue.ALERT: return profile.alert
		Cue.SEARCH: return profile.search
		Cue.WINDUP: return profile.windup
		Cue.STRIKE: return profile.strike
		Cue.MISS: return profile.miss
	return []

func _publish(kind: int) -> void:
	if not multiplayer.is_server(): return
	if kind != Cue.CANCEL and (not _active() or _clock < float(_cooldowns.get(kind, 0.0))): return
	if kind == Cue.ALERT: _cooldowns[kind] = _clock + profile.alert_cooldown
	if kind == Cue.SEARCH: _cooldowns[kind] = _clock + profile.search_cooldown
	var clips := _clips(kind)
	if kind != Cue.CANCEL and clips.is_empty(): return
	var variation := _rng.randi_range(0, maxi(0, clips.size() - 1))
	var pitch := voice_pitch * _rng.randf_range(.98, 1.02)
	_serial += 1
	_receive_event(kind, _serial, variation, pitch)
	if _actor.has_method("_ready_peers"):
		for peer in _actor._ready_peers(): _receive_event.rpc_id(peer, kind, _serial, variation, pitch)

@rpc("authority", "call_remote", "reliable", 2)
func _receive_event(kind: int, sequence: int, variation: int, pitch: float) -> void:
	if kind < 0 or kind >= CUE_NAMES.size() or sequence <= _received: return
	_received = sequence
	if kind == Cue.CANCEL:
		_pending = _pending.filter(func(event): return int(event.kind) != Cue.WINDUP)
		if _cue_kind == Cue.WINDUP: _cue.stop(); _cue_muffled.stop()
		return
	var camera := get_viewport().get_camera_3d()
	if not _active() or camera == null or camera.global_position.distance_to(global_position) >= profile.cue_distance: return
	_pending.append({"kind":kind, "sequence":sequence, "variation":variation, "pitch":clampf(pitch,.5,2.0)})
	if _pending.size() > 4: _pending.pop_front()

func _consume_events() -> void:
	var winner := {}
	for event in _pending:
		if winner.is_empty() or PRIORITIES[int(event.kind)] >= PRIORITIES[int(winner.kind)]: winner = event
	_pending.clear()
	if winner.is_empty(): return
	var kind: int = winner.kind
	if _cue.playing and _cue_priority > PRIORITIES[kind]: return
	var clips := _clips(kind)
	if clips.is_empty(): return
	stop(); _voice_muffled.stop()
	countdown = _next_pause()
	_cue_kind = kind; _cue_priority = PRIORITIES[kind]
	_play_pair(_cue, _cue_muffled, clips[posmod(int(winner.variation), clips.size())], float(winner.pitch))
	sound_played.emit(CUE_NAMES[kind], int(winner.sequence))

func _on_spotted(_target: Node3D) -> void:
	if not multiplayer.is_server(): return
	_loss_left = -1.0
	_publish(Cue.ALERT)

func _on_lost(_point: Vector3) -> void:
	if multiplayer.is_server(): _loss_left = profile.loss_confirmation

func _update_loss(delta: float) -> void:
	if not multiplayer.is_server() or _loss_left < 0.0: return
	_loss_left -= delta
	if _loss_left <= 0.0:
		_loss_left = -1.0
		if _actor.get("_sees_target") != true: _publish(Cue.SEARCH)

func _on_attack_started(_target: Node3D, _duration: float) -> void:
	_cancelled_finish = false
	_publish(Cue.WINDUP)

func _on_attack_cancelled() -> void:
	_cancelled_finish = true
	_publish(Cue.CANCEL)

func _on_attack_finished(_target: Node3D, landed: bool) -> void:
	if _cancelled_finish:
		_cancelled_finish = false
		return
	_publish(Cue.STRIKE if landed else Cue.MISS)

func _reset_contacts() -> void:
	_previous_phase = -1.0
	_previous_clip = &""
	_distance = 0.0

func _update_feet(movement: Vector3, delta: float) -> void:
	var visual := _actor.get("visual") as MonsterVisual
	var travel := Vector2(movement.x,movement.z).length()
	_feet_idle += delta
	if _feet_idle > 0.4: _feet.stop(); _feet_muffled.stop()
	if travel > 3.0 or travel < 0.0001 or _actor.get("_moving") != true:
		_reset_contacts()
		return
	if visual != null and profile.animation_contacts and visual.animator != null and not visual.walk_animation.is_empty() and visual.animator.current_animation == visual.walk_animation:
		var length := visual.animator.get_animation(visual.walk_animation).length
		var phase := fposmod(visual.animator.current_animation_position, maxf(length,0.001)) / maxf(length,0.001)
		if _previous_phase < 0.0 or _previous_clip != visual.walk_animation:
			_previous_phase = phase
			_previous_clip = visual.walk_animation
			return
		var contacts := 0
		for contact in profile.contact_phases:
			if (phase >= _previous_phase and contact > _previous_phase and contact <= phase) or (phase < _previous_phase and (contact > _previous_phase or contact <= phase)): contacts += 1
		_previous_phase = phase
		if contacts > 0: _footstep(phase)
	else:
		_distance += travel
		if _distance >= profile.fallback_stride:
			_distance = fmod(_distance,profile.fallback_stride)
			_footstep(-1.0)

func _footstep(phase: float) -> void:
	if _step_left > 0.0 or _listener == null or _listener.global_position.distance_to(global_position) >= profile.step_distance: return
	_step_left = profile.minimum_step_interval
	if not _actor is CollisionObject3D: return
	if _surface_left <= 0.0:
		_surface_left = 0.08
		var point := _actor.global_position
		var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP*.2, point - Vector3.UP*.4, 1, [_actor.get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		_supported = not hit.is_empty()
		if _supported: _surface = ContactSurface.classify(hit.collider)
	if not _supported: return
	var clips := profile.snow_steps if _surface == &"snow" else profile.metal_steps if _surface == &"metal" else profile.floor_steps
	var sample := _sample(clips, _surface)
	if sample == null: return
	var pitch := _rng.randf_range(.96,1.04)
	var gain := _rng.randf_range(-1.0,0.5)
	for player in [_feet, _feet_muffled]:
		if not player.playing: player.play()
		var playback := player.get_stream_playback() as AudioStreamPlaybackPolyphonic
		if playback != null: playback.play_stream(sample,0.0,gain,pitch)
	_feet_idle = 0.0
	_silent = false
	footstep_played.emit(_surface,phase)

func _stop_all() -> void:
	_was_audible = false
	if _silent and _pending.is_empty():
		_reset_contacts()
		return
	_silent = true
	for player in [self,_voice_muffled,_cue,_cue_muffled,_feet,_feet_muffled]: player.stop()
	_pending.clear()
	_reset_contacts()
