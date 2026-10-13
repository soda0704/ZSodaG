extends "res://tools/tests/character_multiplayer_regression.gd"
## Reuse the real production player network run and sample the owner's render.

var view_frames := 0
var render_gap := 0.0
var view_stages := {}

func _ready() -> void:
	get_tree().root.mode = Window.MODE_WINDOWED
	RenderingServer.frame_post_draw.connect(sample_view)
	super._ready()

func _process(_delta: float) -> void:
	Engine.max_fps = 60 if host else 144
	get_tree().root.position = Vector2i(2200, 1300)

func sample_view() -> void:
	var actor := local_player()
	if actor == null or actor.body_animator.first_person == null: return
	var fp := actor.body_animator.first_person
	if not fp.overlay.visible: return
	view_frames += 1
	view_stages[stage] = true
	render_gap = maxf(render_gap, fp.model.get_global_transform_interpolated().origin.distance_to(fp.model.global_position))

@rpc("authority", "call_remote", "reliable")
func finish(code: int) -> void:
	check(view_frames > 100, "actual network client renders its own first-person model")
	check(view_stages.has("rifle_walk") and view_stages.has("rifle_run") and view_stages.has("pistol"), "client view is sampled during walking, running and pistol use")
	check(render_gap < 0.002, "network client's rig and view camera stay on the same render frame")
	print("NETWORK VIEW METRICS frames=", view_frames, " render_gap=", render_gap)
	print("CLIENT NETWORK CHECKS FAILURES ", failures)
	get_tree().quit(1 if code or failures else 0)
