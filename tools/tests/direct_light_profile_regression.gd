extends SceneTree
var failed := 0
func check(ok: bool, label: String) -> void:
 print("PASS " if ok else "FAIL ", label)
 if not ok: failed += 1
func _initialize() -> void:
 run.call_deferred()
func run() -> void:
 var quality = root.get_node("GameMenu/GraphicsQuality")
 check(not quality.normalized({"GIQuality":3}).has("GIQuality"), "legacy GI setting cannot re-enable global illumination")
 check(not quality.migrate_saved({"GIQuality":3,"MotionBlur":true},3).has("GIQuality"), "saved GI setting is removed during migration")
 check(quality.migrate_saved({"MotionBlur":true},3).MotionBlur, "migration preserves explicit motion blur choice")
 for preset in quality.PRESETS.values():
  quality.apply(preset)
  var env := Environment.new()
  env.sdfgi_enabled = true
  env.ssil_enabled = true
  quality.apply_environment(env)
  check(not env.sdfgi_enabled and not env.ssil_enabled, "preset excludes expensive indirect lighting paths")
 quality.apply(quality.PRESETS[3])
 check(root.positional_shadow_atlas_size == 8192, "High shadows allocate higher resolution than Medium")
 var scene = load("res://scenes/levels/base_blockout_v03.tscn").instantiate()
 check(scene.find_children("*", "VoxelGI", true, false).is_empty(), "production base contains no GI probes")
 check(scene.get_node_or_null("WorldIndirectLighting") == null, "production base contains no GI controller")
 scene.free()
 print("DIRECT LIGHT FAILURES ", failed)
 quit(failed)

