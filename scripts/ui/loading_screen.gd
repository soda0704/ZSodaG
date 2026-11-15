extends Control
## Presentation only; the existing session controller owns the actual loading.
@export var tips: Array[LoadingTip] = []
@export_range(3.0, 30.0) var tip_seconds := 5.0
@export var music_volume_db := -12.0
@onready var music: AudioStreamPlayer = $Music
@onready var logo: TextureRect = $Footer/Content/Status/Logo
@onready var progress_bar: ColorRect = %LoadingProgress
var _progress_target := 0.0
var displayed_progress := 0.0
var _logo_tween: Tween
@onready var footer: MarginContainer = $Footer
@onready var status: Label = %TransitionLabel
@onready var tip_title: Label = %TipTitle
@onready var tip_body: Label = %TipBody
var tip_index := 0
var _tip_elapsed := 0.0
var _tip_tween: Tween
var _tip_changing := false
var _music_tween: Tween
var _previous_mouse_mode := Input.MOUSE_MODE_VISIBLE
var _owns_mouse := false

func _ready() -> void:
	get_viewport().size_changed.connect(_layout)
	get_node("/root/SteamInput").input_device_changed.connect(_refresh_tip)
	visibility_changed.connect(_visibility_changed)
	progress_bar.resized.connect(_sync_progress_size)
	_sync_progress_size()
	_layout()
	_refresh_tip()
	set_process(false)

func show_cover(message: String) -> void:
	_progress_target = 0.0
	displayed_progress = 0.0
	_update_progress_material()
	if not _owns_mouse:
		_previous_mouse_mode = Input.mouse_mode
		_owns_mouse = true
	# Gameplay also polls held buttons, so consuming events alone is not enough.
	# Reuse its existing non-captured-input gate while the cover is present.
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	show()
	modulate = Color.WHITE
	status.text = message
	_reset_tip_transition()
	tip_index = 0
	_tip_elapsed = 0.0
	_refresh_tip()
	if is_instance_valid(_logo_tween): _logo_tween.kill()
	logo.modulate.a = 1.0
	if not NorthernMenuStyle.reduced_motion:
		_logo_tween = create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_logo_tween.tween_property(logo, "modulate:a", 0.72, 1.25)
		_logo_tween.tween_property(logo, "modulate:a", 1.0, 1.25)
	if is_instance_valid(_music_tween): _music_tween.kill()
	music.volume_linear = 0.0
	music.play()
	_music_tween = create_tween()
	_music_tween.tween_property(music, "volume_linear", db_to_linear(music_volume_db), 1.5).set_trans(Tween.TRANS_SINE)
	set_process(true)

func fade_music(seconds: float) -> void:
	if is_instance_valid(_music_tween): _music_tween.kill()
	_music_tween = create_tween()
	_music_tween.tween_property(music, "volume_linear", 0.0, seconds)

func _visibility_changed() -> void:
	if not is_node_ready() or is_visible_in_tree(): return
	set_process(false)
	_reset_tip_transition()
	music.stop()
	if is_instance_valid(_logo_tween): _logo_tween.kill()
	logo.modulate.a = 1.0
	if is_instance_valid(_music_tween): _music_tween.kill()
	_restore_mouse()

func _exit_tree() -> void:
	_restore_mouse()

func _restore_mouse() -> void:
	if _owns_mouse and Input.mouse_mode == Input.MOUSE_MODE_HIDDEN:
		Input.mouse_mode = _previous_mouse_mode
	_owns_mouse = false

func _process(delta: float) -> void:
	displayed_progress = minf(_progress_target, displayed_progress + delta * 1.8)
	_update_progress_material()
	_tip_elapsed += delta
	if _tip_elapsed >= tip_seconds: next_tip()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree(): return
	var space: bool = event is InputEventKey and (event.physical_keycode == KEY_SPACE or event.keycode == KEY_SPACE)
	var controller_accept: bool = event is InputEventJoypadButton or event is InputEventAction
	if event.is_pressed() and not event.is_echo() and (space or (controller_accept and event.is_action_pressed(&"ui_accept"))):
		next_tip()
	# A loading-screen key press must not also jump, fire or open the journal.
	get_viewport().set_input_as_handled()

func next_tip() -> void:
	if tips.is_empty() or _tip_changing: return
	_tip_elapsed = 0.0
	_tip_changing = true
	_tip_tween = create_tween()
	_tip_tween.tween_property(tip_title, "modulate:a", 0.0, 0.15)
	_tip_tween.parallel().tween_property(tip_body, "modulate:a", 0.0, 0.15)
	_tip_tween.chain().tween_callback(func():
		tip_index = (tip_index + 1) % tips.size()
		_refresh_tip()
	)
	_tip_tween.chain().tween_property(tip_title, "modulate:a", 1.0, 0.25)
	_tip_tween.parallel().tween_property(tip_body, "modulate:a", 1.0, 0.25)
	_tip_tween.chain().tween_callback(func(): _tip_changing = false)

func _reset_tip_transition() -> void:
	if is_instance_valid(_tip_tween): _tip_tween.kill()
	_tip_changing = false
	tip_title.modulate.a = 1.0
	tip_body.modulate.a = 1.0

func _refresh_tip() -> void:
	if not is_node_ready() or tips.is_empty(): return
	var service := get_node("/root/SteamInput")
	var copy := tips[tip_index].body
	for action in [&"offer_item", &"interact", &"journal"]:
		copy = copy.replace("{" + str(action) + "}", service.get_action_hint(action))
	tip_title.text = tips[tip_index].title
	tip_body.text = copy

func _layout() -> void:
	# Native containers wrap copy; physical window size sets the same readable
	# minimum as the gameplay HUD, including small and ultrawide windows.
	var factor := preload("res://scripts/ui/hud_layout.gd").scale_for(get_viewport()) * (2560.0 / 1920.0)
	footer.scale = Vector2.ONE * factor
	footer.pivot_offset = Vector2(0, 270)
	footer.offset_left = 0.0
	footer.offset_right = get_viewport_rect().size.x / factor
	footer.offset_top = -270.0
	footer.offset_bottom = 0.0

func set_progress(value: float) -> void:
	if not is_finite(value): return
	_progress_target = maxf(_progress_target, clampf(value, 0.0, 1.0))
	if NorthernMenuStyle.reduced_motion:
		displayed_progress = _progress_target
		_update_progress_material()

func finish_progress() -> void:
	set_progress(1.0)
	while is_visible_in_tree() and displayed_progress < 1.0:
		await get_tree().process_frame

func _sync_progress_size() -> void:
	(progress_bar.material as ShaderMaterial).set_shader_parameter("slider_aspect", progress_bar.size.x / maxf(progress_bar.size.y, 1.0))

func _update_progress_material() -> void:
	var material := progress_bar.material as ShaderMaterial
	material.set_shader_parameter("fill_ratio", displayed_progress)
	material.set_shader_parameter("tip_pulse_speed", 0.0 if NorthernMenuStyle.reduced_motion else 0.8)
