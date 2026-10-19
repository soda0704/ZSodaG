extends SceneTree


func _initialize() -> void:
	_write_identity.call_deferred()


func _write_identity() -> void:
	var config := ConfigFile.new()
	config.set_value("build", "identity", SteamNetworkService.compute_source_identity())
	var result := config.save(SteamNetworkService.BUILD_ID_PATH)
	if result != OK:
		push_error("Could not write build identity: %s" % error_string(result))
	# Let autoload initialization and pending resource releases finish before exit.
	for frame in 8:
		await process_frame
	for player: AudioStreamPlayer in root.find_children("*", "AudioStreamPlayer", true, false):
		player.stop()
		player.stream = null
	await create_timer(0.1).timeout
	quit(0 if result == OK else 1)
