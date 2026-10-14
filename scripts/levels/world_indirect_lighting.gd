@tool
extends Node3D
## Floors have disjoint vertical bounds. Camera facing never selects GI zones.
var _active_count := 0
var _render_states:Dictionary={}
var _data_paths:Dictionary={}
var _failed_paths:Dictionary={}

func _ready() -> void:
	visibility_changed.connect(func()->void:_render_states.clear())
	for probe in get_children():
		probe.visibility_changed.connect(func()->void:_render_states.erase(probe))
		if probe.data!=null:_data_paths[probe]=probe.data.resource_path

func _process(_delta: float) -> void:
	var camera:Camera3D
	if Engine.is_editor_hint():
		var editor:=Engine.get_singleton("EditorInterface")
		if editor==null:return
		var viewport:SubViewport=editor.get_editor_viewport_3d(0)
		camera=viewport.get_camera_3d()
	else:
		camera=get_viewport().get_camera_3d()
	if camera==null:return
	update_floor(camera.global_position.y)

func update_floor(height:float) -> void:
	_active_count=0
	for probe:VoxelGI in get_children():
		var distance:=absf(height-probe.global_position.y)
		# Surface probes shade the base even from a distant or elevated exterior
		# camera. Culling them by camera height changed the visible facade lighting.
		var surface_view:=height>=-8.0 and probe.global_position.y>=0.0
		if not Engine.is_editor_hint():
			# Keep only this floor and an approaching neighbouring floor resident.
			# Hidden instances retain their GPU lighting volumes until data is detached.
			if surface_view or distance<probe.size.y*0.5+6.0:
				if probe.data==null and _data_paths.has(probe) and not _failed_paths.has(probe):
					probe.data=load(_data_paths[probe]) as VoxelGIData
					if probe.data==null:_failed_paths[probe]=true
			elif probe.data!=null:probe.data=null
		var active:=(surface_view or distance<probe.size.y*0.5+2.0) and probe.data!=null and probe.is_visible_in_tree()
		if active:_active_count+=1
		# Backend-only visibility keeps the authored scene and editor undo intact.
		if _render_states.get(probe,null)!=active:
			RenderingServer.instance_set_visible(probe.get_instance(),active)
			_render_states[probe]=active

func get_active_probe_count() -> int:return _active_count

func _exit_tree() -> void:
	if not Engine.is_editor_hint():return
	for probe:VoxelGI in get_children():
		RenderingServer.instance_set_visible(probe.get_instance(),probe.is_visible_in_tree())
