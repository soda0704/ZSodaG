extends SceneTree
## Offline asset authoring only. The game loads the saved mesh and collision.
const OUT := "res://assets/environments/elevator/"
const SEGMENTS := 192
const SIDE_SAMPLES := SEGMENTS / 4
const ROWS := 128
const DEPTH := 10.0
const LAYERS := [0.0, 0.62, 1.51, 2.73, 3.24, 4.81, 5.64, 6.77, 8.23, 8.89, 10.6]
var vertices := PackedVector3Array()
var indices := PackedInt32Array()
var colors := PackedColorArray()
var coarse := FastNoiseLite.new()
var detail := FastNoiseLite.new()
var weathering := FastNoiseLite.new()

func _initialize() -> void:
	run.call_deferred()

func perimeter(i: int) -> Vector2:
	var side := (i % SEGMENTS) / SIDE_SAMPLES
	var t := float(i % SIDE_SAMPLES) / SIDE_SAMPLES
	match side:
		0: return Vector2(lerpf(-1, 1, t), -1)
		1: return Vector2(1, lerpf(-1, 1, t))
		2: return Vector2(lerpf(1, -1, t), 1)
		_: return Vector2(-1, lerpf(1, -1, t))

func triangle(a: int, b: int, c: int, facing: Vector3) -> void:
	# Godot uses clockwise front faces.
	if (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a]).dot(facing) > 0:
		indices.append_array(PackedInt32Array([a, c, b]))
	else:
		indices.append_array(PackedInt32Array([a, b, c]))

func quad(a: int, b: int, c: int, d: int, facing: Vector3) -> void:
	triangle(a, b, c, facing)
	triangle(a, c, d, facing)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	coarse.seed = 73491; coarse.frequency = 0.62; coarse.fractal_octaves = 3
	detail.seed = 21837; detail.frequency = 2.1; detail.fractal_octaves = 2
	weathering.seed = 59213; weathering.frequency = 0.27; weathering.fractal_octaves = 2
	# A closed solid annular shell: open central bore, continuous corners and rim.
	# Uneven rock strata are sculpted into the walls, never into the cabin envelope.
	for row in ROWS + 1:
		var depth := DEPTH * float(row) / ROWS
		for i in SEGMENTS:
			var p := perimeter(i)
			var angle := TAU * float(i) / SEGMENTS
			var sample := Vector3(p.x * 4.0, -depth, p.y * 4.0)
			var broad := coarse.get_noise_3dv(sample)
			var chips := detail.get_noise_3dv(sample)
			var warp := 0.24 * coarse.get_noise_3d(sample.x, depth * 0.13, sample.z)
			var strata := 0.0
			# Unequal, tilted beds with narrow recessed joints instead of repeated rings.
			for layer in range(1, LAYERS.size() - 1):
				var boundary: float = LAYERS[layer] + warp + 0.06 * sample.x - 0.035 * sample.z
				var joint := (depth - boundary) / (0.055 + 0.015 * (layer % 3))
				strata += (0.16 + 0.035 * (layer % 4)) * exp(-joint * joint)
			var fault_a := (0.58 * sample.x + 0.82 * sample.z + depth * 0.24 - 1.3) / 0.10
			var fault_b := (0.86 * sample.x - 0.51 * sample.z - depth * 0.17 + 2.1) / 0.09
			var fractures := 0.12 * exp(-fault_a * fault_a) + 0.09 * exp(-fault_b * fault_b)
			var width := clampf(4.04 + 0.48 * broad + 0.17 * chips + strata + fractures, 3.74, 4.65)
			# Knock back the perfectly square corners, retaining the cabin clearance.
			var bevel := maxf(0.0, absf(p.x) + absf(p.y) - 1.72) * 0.25
			var outline := p - Vector2(signf(p.x), signf(p.y)) * bevel
			var y := -0.08 - depth + 0.035 * sin(angle * 5.0 + depth) * sin(PI * depth / DEPTH)
			vertices.append(Vector3(outline.x * width, y, outline.y * width))
			# Subtle mineral variation and uneven damp streaks; baked vertex data.
			var mineral := weathering.get_noise_3dv(sample)
			var streak := maxf(0.0, detail.get_noise_3d(sample.x * 1.8, depth * 0.08, sample.z * 1.8))
			var shade := clampf(0.91 + mineral * 0.15 - streak * 0.18, 0.73, 1.0)
			colors.append(Color(shade, shade * (0.985 + 0.025 * mineral), shade * (0.96 + 0.03 * mineral), 1))
	for row in ROWS:
		for i in SEGMENTS:
			var next := (i + 1) % SEGMENTS
			var a := row * SEGMENTS + i
			var p := perimeter(i)
			quad(a, row * SEGMENTS + next, (row + 1) * SEGMENTS + next, a + SEGMENTS, Vector3(-p.x, 0, -p.y))
	var outer := vertices.size()
	for row in 2:
		for i in SEGMENTS:
			var p := perimeter(i)
			vertices.append(Vector3(p.x * 7.5, -0.08 - DEPTH * row, p.y * 7.5))
			colors.append(Color(0.88, 0.87, 0.85, 1))
	for i in SEGMENTS:
		var next := (i + 1) % SEGMENTS
		var p := perimeter(i)
		quad(i, outer + i, outer + next, next, Vector3.UP)
		quad(ROWS * SEGMENTS + i, ROWS * SEGMENTS + next, outer + SEGMENTS + next, outer + SEGMENTS + i, Vector3.DOWN)
		quad(outer + i, outer + SEGMENTS + i, outer + SEGMENTS + next, outer + next, Vector3(p.x, 0, p.y))
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in vertices.size():
		surface.set_color(colors[i])
		surface.add_vertex(vertices[i])
	for index in indices:
		surface.add_index(index)
	surface.generate_normals()
	var mesh := surface.commit()
	mesh.surface_set_material(0, load(OUT + "shaft_limestone.tres"))
	assert(ResourceSaver.save(mesh, OUT + "surface_shaft_rock.res", ResourceSaver.FLAG_COMPRESS) == OK)
	mesh.take_over_path(OUT + "surface_shaft_rock.res")
	var collision := mesh.create_trimesh_shape()
	collision.backface_collision = true
	assert(ResourceSaver.save(collision, OUT + "surface_shaft_rock_collision.res", ResourceSaver.FLAG_COMPRESS) == OK)
	print("SURFACE_SHAFT_ROCK: ", indices.size() / 3, " triangles; bounds ", mesh.get_aabb())
	quit()
