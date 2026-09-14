extends SceneTree

const OUT := "res://assets/environments/snow/"
const DATA := OUT + "terrain_data/"
var noise := FastNoiseLite.new()

func _initialize() -> void:
	generate.call_deferred()

func height_at(x: float, z: float) -> float:
	var edge := Vector2(maxf(absf(x) - 48.0, 0), maxf(absf(z) - 38.0, 0)).length()
	var blend := smoothstep(3.0, 48.0, edge)
	var hills := 4.0 + noise.get_noise_2d(x, z) * 9.0
	hills += 14.0 * exp(-pow((x - 125.0) / 58.0, 2) - pow((z + 75.0) / 88.0, 2))
	hills += 10.0 * exp(-pow((x + 120.0) / 70.0, 2) - pow((z - 105.0) / 65.0, 2))
	hills += smoothstep(150.0, 235.0, Vector2(x, z).length()) * 18.0
	var road_z := 9.0 + sin((x + 45.0) * 0.025) * 12.0
	var road := (1.0 - smoothstep(3.0, 9.0, absf(z - road_z))) if x < -42.0 else 0.0
	return lerpf(-0.25, hills * (1.0 - road * 0.75), blend)

func material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.92
	return mat

func add_mesh(parent: Node3D, mesh: Mesh, pos: Vector3, label: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	parent.add_child(node)
	node.owner = parent
	node.position = pos
	node.layers = 1 | (1 << 18)
	return node

func instances(parent: Node3D, mesh: Mesh, poses: Array[Transform3D], label: String) -> void:
	var node := MultiMeshInstance3D.new()
	node.name = label
	node.multimesh = MultiMesh.new()
	node.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	node.multimesh.mesh = mesh
	node.multimesh.instance_count = poses.size()
	for i in poses.size():
		node.multimesh.set_instance_transform(i, poses[i])
	node.layers = 1 | (1 << 18)
	parent.add_child(node)
	node.owner = parent

func obstacle(parent: Node3D, at: Vector3, radius: float, height: float) -> void:
	var body := StaticBody3D.new()
	parent.add_child(body)
	body.owner = parent
	body.position = at + Vector3.UP * height * 0.5
	var collider := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	collider.shape = shape
	body.add_child(collider)
	collider.owner = parent

func generate() -> void:
	DirAccess.make_dir_recursive_absolute(DATA)
	noise.seed = 140926
	noise.frequency = 0.018
	noise.fractal_octaves = 4
	var exterior := Node3D.new()
	exterior.name = "SnowExterior"
	exterior.set_script(load("res://scripts/levels/snow_exterior.gd"))
	root.add_child(exterior)
	current_scene = exterior
	var terrain := Terrain3D.new()
	terrain.name = "Terrain3D"
	terrain.region_size = 256
	terrain.free_editor_textures = false
	terrain.collision_mode = Terrain3DCollision.FULL_GAME
	terrain.render_layers = 1 | (1 << 18)
	terrain.material = Terrain3DMaterial.new()
	terrain.material.world_background = 0
	terrain.assets = Terrain3DAssets.new()
	var snow := Terrain3DTextureAsset.new()
	snow.name = "Wind packed snow"
	snow.albedo_color = Color(0.89, 0.94, 0.98)
	snow.roughness = 1.0
	snow.uv_scale = 0.5
	var texture := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	for y in 128:
		for x in 128:
			var value := 0.88 + noise.get_noise_2d(x * 12, y * 12) * 0.10
			texture.set_pixel(x, y, Color(value, value, value, 0.5))
	texture.generate_mipmaps()
	snow.albedo_texture = ImageTexture.create_from_image(texture)
	terrain.assets.texture_list = [snow]
	exterior.add_child(terrain)
	terrain.owner = exterior
	var heights := Image.create(512, 512, false, Image.FORMAT_RF)
	var colors := Image.create(512, 512, false, Image.FORMAT_RGBA8)
	for z in 512:
		for x in 512:
			var px := float(x - 256)
			var pz := float(z - 256)
			heights.set_pixel(x, z, Color(height_at(px, pz), 0, 0))
			var tint := 0.92 + noise.get_noise_2d(px * 2.4, pz * 2.4) * 0.08
			colors.set_pixel(x, z, Color(tint, tint, tint, 1))
	terrain.data.import_images([heights, null, colors], Vector3(-256, 0, -256))
	# Keep the central shaft open while ground sits below the existing floor.
	for z in range(-4, 4):
		for x in range(-4, 4):
			terrain.data.set_control_hole(Vector3(x, 0, z), true)
	terrain.data.update_maps()
	terrain.data.save_directory(DATA)
	terrain.data_directory = DATA
	var rng := RandomNumberGenerator.new()
	rng.seed = 27410
	var trunks: Array[Transform3D] = []
	var branches: Array[Transform3D] = []
	var snow_branches: Array[Transform3D] = []
	var rocks: Array[Transform3D] = []
	var snow_rocks: Array[Transform3D] = []
	for i in 380:
		var x := rng.randf_range(-225, 225)
		var z := rng.randf_range(-225, 225)
		if absf(x) < 58 and absf(z) < 49:
			continue
		var road := 9.0 + sin((x + 45) * 0.025) * 12.0
		if x < -42 and absf(z - road) < 11:
			continue
		var at := Vector3(x, height_at(x, z), z)
		var s := rng.randf_range(0.7, 1.8)
		var angle := rng.randf() * TAU
		if i % 4 == 0:
			obstacle(exterior, at, s * 1.5, s * 2.0)
			var size := Vector3(s * 2.5, s * 1.8, s * 1.7)
			rocks.append(Transform3D(Basis(Vector3.UP, angle).scaled(size), at + Vector3.UP * s * 0.6))
			snow_rocks.append(Transform3D(Basis(Vector3.UP, angle).scaled(size * Vector3(0.9, 0.25, 0.9)), at + Vector3.UP * s * 1.8))
		else:
			obstacle(exterior, at, s * 0.20, s * 6.0)
			trunks.append(Transform3D(Basis.IDENTITY.scaled(Vector3(s * 0.22, s * 7, s * 0.22)), at + Vector3.UP * s * 3.5))
			for tier in 4:
				var radius := (2.2 - tier * 0.4) * s
				var center := at + Vector3.UP * (2.0 + tier * 1.35) * s
				branches.append(Transform3D(Basis(Vector3.UP, angle).scaled(Vector3(radius, 2.8 * s, radius)), center))
				snow_branches.append(Transform3D(Basis(Vector3.UP, angle).scaled(Vector3(radius * 0.94, 2.4 * s, radius * 0.94)), center + Vector3.UP * 0.25 * s))
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.6
	trunk.bottom_radius = 1.0
	trunk.height = 1
	trunk.radial_segments = 7
	trunk.material = material(Color("514c49"))
	instances(exterior, trunk, trunks, "PineTrunks")
	var cone := CylinderMesh.new()
	cone.top_radius = 0
	cone.bottom_radius = 1
	cone.height = 1
	cone.radial_segments = 9
	cone.material = material(Color("364b4b"))
	instances(exterior, cone, branches, "PineBranches")
	var white_cone := cone.duplicate() as CylinderMesh
	white_cone.material = material(Color("dce6e9"))
	instances(exterior, white_cone, snow_branches, "PineSnow")
	var rock := SphereMesh.new()
	rock.radius = 1
	rock.height = 2
	rock.radial_segments = 7
	rock.rings = 3
	rock.material = material(Color("505d68"))
	instances(exterior, rock, rocks, "RockOutcrops")
	var cap := rock.duplicate() as SphereMesh
	cap.material = material(Color("dae5eb"))
	instances(exterior, cap, snow_rocks, "RockSnow")
	# A closed buried shell prevents seeing the lower blockout from the edge.
	for spec in [[Vector3(512, 180, 2), Vector3(0, -75, -255)], [Vector3(512, 180, 2), Vector3(0, -75, 255)], [Vector3(2, 180, 512), Vector3(-255, -75, 0)], [Vector3(2, 180, 512), Vector3(255, -75, 0)]]:
		var box := BoxMesh.new()
		box.size = spec[0]
		box.material = material(Color("69757f"))
		add_mesh(exterior, box, spec[1], "BuriedRockShell")
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var panorama := PanoramaSkyMaterial.new()
	panorama.panorama = load(OUT + "overcast_soil_puresky_4k.exr")
	sky.sky_material = panorama
	environment.sky = sky
	environment.background_energy_multiplier = 0.35
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("bdd0df")
	environment.ambient_light_energy = 0.25
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color("c4d4e1")
	environment.fog_density = 0.0012
	environment.fog_sky_affect = 0.12
	var world := WorldEnvironment.new()
	world.name = "OvercastDayEnvironment"
	world.environment = environment
	exterior.add_child(world)
	world.owner = exterior
	var sun := DirectionalLight3D.new()
	sun.name = "OvercastDaySun"
	sun.rotation_degrees = Vector3(-48, -32, 0)
	sun.light_color = Color("fff5e4")
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 220
	sun.light_cull_mask = (1 << 18) | (1 << 19)
	exterior.add_child(sun)
	sun.owner = exterior
	var scene := PackedScene.new()
	scene.pack(exterior)
	var result := ResourceSaver.save(scene, "res://scenes/levels/snow_exterior.tscn")
	print("SNOW_EXTERIOR_GENERATED: ", result, " regions=", terrain.data.get_region_count())
	quit(result)
