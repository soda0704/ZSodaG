extends SceneTree


func _initialize() -> void:
	var config := ConfigFile.new()
	config.set_value("build", "identity", SteamNetworkService.compute_source_identity())
	var result := config.save(SteamNetworkService.BUILD_ID_PATH)
	if result != OK:
		push_error("Could not write build identity: %s" % error_string(result))
	quit(0 if result == OK else 1)
