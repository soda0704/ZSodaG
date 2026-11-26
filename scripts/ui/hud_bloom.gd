extends Control
## Render the HUD to a transparent surface and bloom only its own pixels.
const BLOOM := preload("res://assets/shaders/hud_bloom.gdshader")
const INK := preload("res://assets/shaders/hud_ink_composite.gdshader")

var ink := Control.new()
var _source := SubViewport.new()
var _horizontal := SubViewport.new()
var _vertical := SubViewport.new()
var _horizontal_quad: TextureRect
var _vertical_quad: TextureRect
var _core: TextureRect


func _ready() -> void:
	for viewport in [_source, _horizontal, _vertical]:
		viewport.disable_3d = true
		viewport.transparent_bg = true
		viewport.gui_disable_input = true
	add_child(_vertical)
	_vertical.add_child(_horizontal)
	_horizontal.add_child(_source)
	_source.add_child(ink)
	_horizontal_quad = _blur_quad(_horizontal, _source.get_texture(), true)
	_vertical_quad = _blur_quad(_vertical, _horizontal.get_texture(), false)
	_core = _quad(self, _source.get_texture())
	var composite := ShaderMaterial.new()
	composite.shader = INK
	composite.set_shader_parameter("halo", _vertical.get_texture())
	_core.material = composite
	visibility_changed.connect(_update_rendering)
	_update_rendering()


func set_motion_trail(travel: Vector2) -> void:
	_core.material.set_shader_parameter("motion_trail", travel)


func set_glow_enabled(enabled: bool) -> void:
	_core.material.set_shader_parameter("glow_enabled", enabled)


func _update_rendering() -> void:
	var mode := SubViewport.UPDATE_ALWAYS if is_visible_in_tree() else SubViewport.UPDATE_DISABLED
	for viewport in [_source, _horizontal, _vertical]:
		viewport.render_target_update_mode = mode


func fit(extent: Vector2, pixel_extent: Vector2) -> void:
	_source.size = Vector2i(pixel_extent.ceil()).max(Vector2i(2, 2))
	_source.size_2d_override = Vector2i(extent.round()).max(Vector2i.ONE)
	_source.size_2d_override_stretch = true
	var blur_size := Vector2i((_source.size * 0.5).ceil()).max(Vector2i.ONE)
	_horizontal.size = blur_size
	_vertical.size = blur_size
	_horizontal_quad.size = blur_size
	_vertical_quad.size = blur_size
	_horizontal_quad.material.set_shader_parameter("blur_step", Vector2(1.5 / extent.x, 0.0))
	_vertical_quad.material.set_shader_parameter("blur_step", Vector2(0.0, 1.5 / extent.y))
	_core.size = extent


func _blur_quad(viewport: SubViewport, texture: Texture2D, extract: bool) -> TextureRect:
	var quad := _quad(viewport, texture)
	var pass_material := ShaderMaterial.new()
	pass_material.shader = BLOOM
	pass_material.set_shader_parameter("source", texture)
	pass_material.set_shader_parameter("extract_highlights", extract)
	quad.material = pass_material
	return quad


func _quad(parent: Node, texture: Texture2D) -> TextureRect:
	var quad := TextureRect.new()
	quad.texture = texture
	quad.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	quad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quad.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	parent.add_child(quad)
	return quad
