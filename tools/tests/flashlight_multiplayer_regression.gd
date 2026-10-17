extends Node
var actor: GamePlayer
var failures := 0
var checks := 0
var host := false
var client_ready := false
var client_id := 0
func _ready() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
 checks += 1
 if not ok: failures += 1
 print("PASS " if ok else "FAIL ", label)
func make_actor(id: int) -> void:
 actor = load("res://scenes/characters/player.tscn").instantiate()
 actor.name = "TestPlayer"
 actor.setup(id, "Tester", Vector3.ZERO, Color.WHITE)
 add_child(actor)
 actor.set_physics_process(host)
 actor.survival.set_physics_process(false)
func run() -> void:
 var port := 28749
 for arg in OS.get_cmdline_user_args():
  if arg == "--host": host = true
  if arg.begins_with("--port="): port = int(arg.trim_prefix("--port="))
 var peer := ENetMultiplayerPeer.new()
 if host:
  peer.create_server(port, 2)
  multiplayer.multiplayer_peer = peer
  multiplayer.peer_connected.connect(func(id):
   client_id = id
   make_actor(id)
  )
  print("FLASHLIGHT_HOST_READY")
 else:
  peer.create_client("127.0.0.1", port)
  multiplayer.multiplayer_peer = peer
  await multiplayer.connected_to_server
  make_actor(multiplayer.get_unique_id())
  await get_tree().create_timer(0.3).timeout
  announce_ready.rpc_id(1)
  return
 for i in range(100):
  if client_ready: break
  await get_tree().create_timer(0.1).timeout
 if not client_ready:
  check(false, "client becomes ready")
  finish()
  return
 actor.apply_inventory_snapshot({"held_item": &"pistol", "has_flashlight": true, "handheld_flashlight_drawn": true, "battery_charge": 0.0, "weapon_rounds": 3, "pistol_ammo": 20, "spare_batteries": [1.0]})
 actor._publish_inventory()
 await get_tree().create_timer(0.2).timeout
 client_reload.rpc_id(client_id)
 await get_tree().create_timer(1.5).timeout
 check(actor._battery_charge > 0.98 and actor.weapon.rounds == 3 and actor.weapon.reload_left <= 0.0, "client R replaces empty cell before pistol reload on host")
 actor.flashlight.begin_malfunction(true)
 await get_tree().create_timer(0.2).timeout
 client_toggle.rpc_id(client_id)
 await get_tree().create_timer(0.3).timeout
 check(actor._flashlight_malfunctioning and not actor._flashlight_enabled, "client stow/draw cannot clear host fault")
 client_shake.rpc_id(client_id, 1)
 await get_tree().create_timer(0.35).timeout
 check(actor._flashlight_malfunctioning and actor._flashlight_shake_presses == 1, "one client tap remains broken on host")
 client_shake.rpc_id(client_id, 5)
 await get_tree().create_timer(1.3).timeout
 check(not actor._flashlight_malfunctioning and actor._flashlight_enabled and actor.flashlight.beam.visible, "six client taps repair authoritative torch")
 finish_remote.rpc_id(client_id)
 await get_tree().create_timer(0.5).timeout
 finish()
@rpc("any_peer", "reliable")
func announce_ready() -> void:
 if multiplayer.is_server() and multiplayer.get_remote_sender_id() == client_id: client_ready = true
@rpc("authority", "call_remote", "reliable")
func client_reload() -> void:
 check(actor._battery_charge <= 0.0 and actor._held_item_type == &"pistol", "client receives depleted offhand inventory")
 actor.request_reload_or_battery()
@rpc("authority", "call_remote", "reliable")
func client_toggle() -> void:
 check(actor.needs_flashlight_shake() and actor.get_node("PlayerUI/FlashlightShakeHint").visible, "fault and hint reach owning client")
 actor._flashlight_serial += 1
 actor.send_input_if_due(0.1)
 await get_tree().create_timer(0.15).timeout
 actor._flashlight_serial += 1
 actor.send_input_if_due(0.1)
@rpc("authority", "call_remote", "reliable")
func client_shake(count: int) -> void:
 for i in range(count):
  actor.request_inventory_action(&"shake_flashlight")
  await get_tree().create_timer(0.16).timeout
@rpc("authority", "call_remote", "reliable")
func finish_remote() -> void:
 check(not actor._flashlight_malfunctioning and actor._flashlight_enabled and not actor.get_node("PlayerUI/FlashlightShakeHint").visible, "repaired state and hidden hint reach client")
 finish()
func finish() -> void:
 print("FLASHLIGHT COOP CHECKS ", checks, " FAILURES ", failures)
 get_tree().quit(0 if failures == 0 else 1)
