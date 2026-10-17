extends "res://tools/tests/plant_watering_regression.gd"

var socket: PlantSeedSocket
var planting_cycles := 0

func visit_seed() -> void:
 player.teleport_authoritative(Vector3(socket.global_position.x, 0.04, socket.global_position.z + 1.0), 0)
 player.camera.look_at(socket.interaction_point.global_position)
 Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
 await settle()

func run() -> void:
 Engine.max_fps = 60
 await boot()
 socket = container.get_node("PlantSeedSocket")
 socket.animation.animation_started.connect(func(clip: StringName):
  if clip == &"plant": planting_cycles += 1)
 check(not state.plant_seed_planted, "fresh container has no seed")
 check(not state.water_plant_authoritative(1), "empty soil cannot be watered")
 check(not state.plant_seed_authoritative(1), "planting without packet rejected")
 var packet := base.get_node("KitchenSeedPacket") as WorldItemPickup
 check(packet.highlight_category == WorldItemPickup.HighlightCategory.SPECIAL, "seed packet uses pink special-item focus")
 check(packet.global_position.distance_to(base.get_seed_packet_spawn_transform().origin) < 0.2, "packet stays on kitchen counter")
 player.teleport_authoritative(packet.global_position + Vector3(0, 0, 0.7), 0)
 await settle()
 packet.network_interact(1, player)
 await settle()
 check(player.has_held_item(GamePlayer.SEED_ITEM), "ordinary world pickup puts seed packet in hand")
 check(player.held_seed_packet.visible and not player.held_fuse.visible, "packet has its own held visual")
 player.drop_current_item_authoritative()
 await settle()
 var dropped: WorldItemPickup
 for item in get_nodes_in_group("world_items"):
  if item.item_type == GamePlayer.SEED_ITEM: dropped = item
 check(dropped != null, "dropping creates the same seed packet type")
 if dropped != null: dropped.network_interact(1, player)
 await settle()
 check(player.has_held_item(GamePlayer.SEED_ITEM), "dropped packet can be picked up again")
 player.teleport_authoritative(socket.global_position + Vector3(0, 0, 5), 0)
 await settle()
 check(not state.plant_seed_authoritative(1), "planting beyond reach rejected")
 await visit_seed()
 check(player.get_interaction_target() == socket, "production aim ray reaches planting area")
 check(socket.get_interaction_hint_for(player).ends_with("Посадить семечко"), "only held packet offers contextual planting")
 player.survival.dead = true
 check(not state.plant_seed_authoritative(1), "dead player cannot plant")
 player.survival.dead = false
 check(not state.plant_seed_authoritative(999), "unknown peer cannot plant")
 var blocker := StaticBody3D.new()
 var shape := CollisionShape3D.new()
 shape.shape = BoxShape3D.new()
 shape.shape.size = Vector3(0.6, 0.6, 0.1)
 blocker.add_child(shape)
 base.add_child(blocker)
 blocker.global_position = (player.camera.global_position + socket.interaction_point.global_position) * 0.5
 await settle()
 check(not state.plant_seed_authoritative(1), "planting through wall rejected")
 blocker.queue_free()
 await settle()
 check(not state.main_breaker_on, "manual planting tested before power startup")
 player.try_authoritative_interaction()
 check(state.plant_seed_planted and not player.has_held_item(GamePlayer.SEED_ITEM), "production E plants and consumes one packet on day one")
 check(planting_cycles == 1, "one native planting animation begins")
 check(not state.plant_seed_authoritative(1), "duplicate request cannot plant twice")
 socket.animation.advance(1.9)
 check(socket.seed.visible and socket.seed.position.y < 0.4, "animated seed lands in soil")
 socket.animation.advance(2.0)
 check(socket.seed.visible and not container.get_node("PlantingPacket").visible, "finished action leaves seed, removes temporary packet")
 check(state.load_saved_snapshot().plant_seed_planted, "planted state saved by ordinary host snapshot")
 base.queue_free()
 await process_frame
 await boot()
 socket = container.get_node("PlantSeedSocket")
 check(state.plant_seed_planted and socket.seed.visible, "re-entering restores planted seed")
 check(not base.has_node("KitchenSeedPacket"), "consumed packet does not respawn")
 check(socket.animation.current_animation != &"plant", "loading does not replay planting")
 powered()
 await visit()
 check(state.water_plant_authoritative(1), "planted seed unlocks existing powered daily watering")
 state.reset_day_one_authoritative()
 check(not state.plant_seed_planted and not socket.seed.visible, "new expedition clears planting")
 var later := state.get_snapshot()
 later.day_index = 4
 later.phase = BaseGameplayController.BasePhase.ACTIVE_DAY
 state._broadcast_snapshot(later)
 player.pickup_world_item_authoritative(GamePlayer.SEED_ITEM, {})
 await visit_seed()
 check(state.plant_seed_authoritative(1), "optional planting remains available after day one")
 base.queue_free()
 await process_frame
 print("PLANT SEED CHECKS ", checks, " FAILURES ", failures)
 quit(1 if failures else 0)
