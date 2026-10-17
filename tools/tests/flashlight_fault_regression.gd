extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
 checks += 1
 if not ok: failures += 1
 print("PASS " if ok else "FAIL ", label)
func fixture(player: GamePlayer, kind: StringName, charge: float, fault := false, mounted := false) -> void:
 player.apply_inventory_snapshot({"held_item": kind, "has_flashlight": true, "battery_charge": charge, "malfunctioning": fault, "handheld_flashlight_drawn": kind != &"flashlight" and not mounted, "flashlight_enabled": not fault and charge > 0.0, "weapon_light_mounted": mounted, "weapon_rounds": 3, "pistol_ammo": 20, "spare_batteries": [1.0]})
func run() -> void:
 Engine.max_fps = 60
 root.get_node("GameMenu").force_close_menu()
 root.get_node("SteamInput").set_process(false)
 var arena = load("res://tools/tests/fixtures/character_test_arena.tscn").instantiate()
 root.add_child(arena)
 current_scene = arena
 var player := load("res://scenes/characters/player.tscn").instantiate() as GamePlayer
 player.name = "1"
 player.setup(1, "", Vector3(0, 0.1, 0), Color.WHITE, 0, 0)
 arena.get_node("Players").add_child(player)
 player.survival.set_physics_process(false)
 player.set_physics_process(false)
 for kind in [&"pistol", &"fuel_can", &"flashlight", &"m4a1"]:
  for charge in [0.0, 0.35]:
   fixture(player, kind, charge, false, kind == &"m4a1")
   player.request_reload_or_battery()
   check(player._battery_action_busy and player.weapon.reload_left <= 0.0, "R prioritizes battery for %s charge %.2f" % [kind, charge])
   await create_timer(1.25).timeout
   check(is_equal_approx(player._battery_charge, 1.0) and player._held_item_type == kind, "battery inserted; main item retained")
 fixture(player, &"pistol", 1.0)
 player.request_reload_or_battery()
 check(player.weapon.reload_left > 0.0 and not player._battery_action_busy, "R falls back to weapon reload when battery needs no upgrade")
 player.weapon.reload_left = 0.0
 fixture(player, &"fuel_can", 0.65)
 player.flashlight.begin_malfunction(true)
 check(player._flashlight_malfunctioning and not player._flashlight_enabled, "actual timer callback sets authoritative fault")
 check(player.get_node("PlayerUI/FlashlightShakeHint").visible, "fault displays shake hint for owner")
 player.toggle_flashlight_authoritative()
 player.toggle_flashlight_authoritative()
 check(player._flashlight_malfunctioning and not player.flashlight.beam.visible, "stow/draw cannot repair fault")
 player.pickup_world_item_authoritative(&"pistol", {"rounds": 3})
 check(player._flashlight_malfunctioning and not player._flashlight_enabled, "picking another hand item cannot repair fault")
 var saved := player.get_inventory_snapshot()
 player.apply_inventory_snapshot(saved)
 check(player._flashlight_malfunctioning, "snapshot retains fault")
 var dropped := {"battery_charge": player._battery_charge, "malfunctioning": player._flashlight_malfunctioning}
 player.perform_inventory_action_authoritative(&"drop_flashlight")
 var world_lamp = get_nodes_in_group("world_items").filter(func(item): return item.item_type == &"flashlight").back()
 check(world_lamp.item_state == dropped, "spawned world pickup stores contact fault")
 player.pickup_world_item_authoritative(&"flashlight", world_lamp.item_state)
 check(player.needs_flashlight_shake() and not player.flashlight.beam.visible, "dropped and repicked faulty torch stays broken")
 player.perform_inventory_action_authoritative(&"replace_battery")
 check(player._flashlight_malfunctioning and not player._flashlight_enabled, "fresh battery cannot bypass contact fault")
 player._flashlight_shake_presses = 0
 player._last_flashlight_shake_msec = -1000
 check(player.shake_flashlight_authoritative() and player._flashlight_malfunctioning, "one press is insufficient")
 check(not player.shake_flashlight_authoritative(), "duplicate instant request is rejected")
 for i in range(5):
  await create_timer(0.15).timeout
  Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
  var event := InputEventKey.new()
  event.physical_keycode = KEY_E
  event.pressed = true
  if DisplayServer.get_name() == "headless":
   player.request_inventory_action(&"shake_flashlight")
  else:
   player._unhandled_input(event)
 check(not player._flashlight_malfunctioning and player._flashlight_enabled and player.flashlight.beam.visible, "six separate E presses repair and restore beam")
 check(not player.get_node("PlayerUI/FlashlightShakeHint").visible, "repair dismisses hint")
 var intervals: Array[float] = []
 for i in range(8):
  player.flashlight.set_enabled(false, false)
  player.flashlight.malfunction_timer.stop()
  player.flashlight.set_enabled(true, false)
  intervals.append(player.flashlight.malfunction_timer.wait_time)
 check(intervals.all(func(t): return t >= 60.0 and t <= 120.0) and intervals.max() - intervals.min() > 1.0, "fault intervals vary between authored limits")
 var remaining := player.flashlight.malfunction_timer.time_left
 player.toggle_flashlight_authoritative()
 await create_timer(0.2).timeout
 player.toggle_flashlight_authoritative()
 check(absf(remaining - player.flashlight.malfunction_timer.time_left) < 0.06, "stowing pauses interval instead of rerolling it")
 player.queue_free()
 arena.queue_free()
 await process_frame
 print("FLASHLIGHT FAULT CHECKS ", checks, " FAILURES ", failures)
 quit(0 if failures == 0 else 1)
