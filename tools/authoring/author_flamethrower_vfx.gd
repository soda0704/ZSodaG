extends SceneTree
## Offline authoring only. Runtime uses the saved scene, materials and animation clips.
const DIR := "res://assets/effects/flamethrower/"
var effect: Node3D
func _initialize() -> void: run.call_deferred()
func attach(node: Node, parent: Node) -> void:
	parent.add_child(node); node.owner=effect
func save_resource(value: Resource,path: String) -> void:
	assert(ResourceSaver.save(value,path)==OK);value.take_over_path(path)
func ramp(points: Array) -> CurveTexture:
	var curve:=Curve.new()
	for point: Vector2 in points:curve.add_point(point)
	var result:=CurveTexture.new();result.curve=curve;return result
func particles(label: String,parent: Node,amount: int,life: float,speed: Vector2,spread: float,size: Vector2,scale_curve: CurveTexture,smoky:=false) -> GPUParticles3D:
	var noise:=FastNoiseLite.new();noise.frequency=.025;noise.fractal_octaves=4
	var texture:=NoiseTexture2D.new();texture.width=256;texture.height=256;texture.seamless=true;texture.noise=noise
	var mat:=ShaderMaterial.new();mat.shader=load(DIR+"jet.gdshader");mat.set_shader_parameter("turbulence",texture)
	mat.set_shader_parameter("smoke",smoky)
	mat.set_shader_parameter("opacity",.12 if smoky else .82)
	mat.set_shader_parameter("emission_energy",0.0 if smoky else 1.4)
	mat.set_shader_parameter("hot_tint",Color(.16,.17,.18) if smoky else Color(1,.52,.12))
	mat.set_shader_parameter("cool_tint",Color(.045,.048,.052) if smoky else Color(.61,.055,.004))
	if label=="Core":mat.set_shader_parameter("hot_tint",Color(1,.92,.68));mat.set_shader_parameter("emission_energy",2.2)
	if label=="Embers":mat.set_shader_parameter("hot_tint",Color(1,.28,.025));mat.set_shader_parameter("emission_energy",2.5)
	save_resource(mat,DIR+label.to_snake_case()+"_material.tres")
	var mesh:=QuadMesh.new();mesh.size=size;mesh.material=mat
	var process:=ParticleProcessMaterial.new();process.resource_local_to_scene=true
	process.direction=Vector3.FORWARD;process.spread=spread
	process.emission_shape=ParticleProcessMaterial.EMISSION_SHAPE_SPHERE;process.emission_sphere_radius=.018
	process.initial_velocity_min=speed.x;process.initial_velocity_max=speed.y
	process.gravity=Vector3(0,.55 if smoky else .22,0)
	process.scale_min=.65;process.scale_max=1.15;process.scale_curve=scale_curve
	process.angle_min=-180;process.angle_max=180;process.angular_velocity_min=-55;process.angular_velocity_max=55
	process.turbulence_enabled=false
	var value:=GPUParticles3D.new();value.name=label;value.amount=amount;value.lifetime=life;value.emitting=false
	value.process_material=process;value.draw_pass_1=mesh;value.local_coords=false
	value.visibility_aabb=AABB(Vector3(-9,-5,-9),Vector3(18,12,18));value.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	value.fixed_fps=60;value.draw_order=GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	attach(value,parent);return value
func run() -> void:
	effect=Node3D.new();effect.name="FlameJet";effect.top_level=true;effect.set_script(load("res://scripts/effects/flamethrower_jet.gd"))
	var grow:=ramp([Vector2(0,.12),Vector2(.18,.42),Vector2(.65,1),Vector2(1,.7)])
	particles("Core",effect,320,.26,Vector2(13.5,15),2.5,Vector2(.24,.50),ramp([Vector2(0,.45),Vector2(.2,.65),Vector2(.65,1),Vector2(1,.7)]))
	particles("Flames",effect,210,.53,Vector2(11.8,13.5),4.0,Vector2(.46,.86),grow)
	particles("Smoke",effect,64,1.1,Vector2(4,5.5),8.0,Vector2(.55,.85),grow,true)
	particles("Embers",effect,28,.65,Vector2(7,10),9.0,Vector2(.014,.035),grow)
	var impact:=Node3D.new();impact.name="Impact";attach(impact,effect)
	var splash:=particles("Flames",impact,48,.45,Vector2(.3,.9),65,Vector2(.30,.48),grow)
	splash.process_material.direction=Vector3.UP;splash.process_material.gravity=Vector3(0,.5,0)
	var smoke:=particles("Smoke",impact,24,.9,Vector2(.15,.45),40,Vector2(.45,.6),grow,true)
	smoke.process_material.direction=Vector3.UP
	var glow:=OmniLight3D.new();glow.name="Glow";glow.light_color=Color(1,.39,.085);glow.light_energy=0;glow.omni_range=3.4
	glow.shadow_enabled=false;glow.light_indirect_energy=0;glow.light_volumetric_fog_energy=.15;glow.add_to_group("mobile_interior_lights",true);attach(glow,effect)
	var contact:=OmniLight3D.new();contact.name="Glow";contact.light_color=Color(1,.32,.055);contact.light_energy=0;contact.omni_range=2.2
	contact.light_indirect_energy=0;contact.light_volumetric_fog_energy=.1;contact.add_to_group("mobile_interior_lights",true);attach(contact,impact)
	var audio:=AudioStreamPlayer3D.new();audio.name="Roar";audio.stream=load("res://assets/audio/gameplay/flamethrower_roar.wav")
	audio.stream.loop_mode=AudioStreamWAV.LOOP_FORWARD;audio.stream.loop_begin=0;audio.stream.loop_end=72000
	audio.bus=&"Weapons";audio.volume_db=-60;audio.unit_size=2;audio.max_distance=38;attach(audio,effect)
	var library:=AnimationLibrary.new()
	for clip in ["ignite","burn","extinguish"]:
		var anim:=Animation.new();anim.length=1.2 if clip=="burn" else .16 if clip=="ignite" else .22
		if clip=="burn":anim.loop_mode=Animation.LOOP_LINEAR
		for track_spec in [["Glow:light_energy",1.6],["Impact/Glow:light_energy",.65],["Roar:volume_db",-23.0]]:
			var index:=anim.add_track(Animation.TYPE_VALUE);anim.track_set_path(index,NodePath(track_spec[0]))
			var peak: float=track_spec[1];var silent: float=-60.0 if index==2 else 0.0
			if clip=="burn":
				for key in [Vector2(0,1),Vector2(.17,.82),Vector2(.33,1.06),Vector2(.57,.89),Vector2(.76,1.04),Vector2(.98,.93),Vector2(1.2,1)]:anim.track_insert_key(index,key.x,peak if index==2 else peak*key.y)
			else:
				anim.track_insert_key(index,0,silent if clip=="ignite" else peak)
				anim.track_insert_key(index,anim.length,peak if clip=="ignite" else silent)
		library.add_animation(clip,anim)
	var animator:=AnimationPlayer.new();animator.name="AnimationPlayer";animator.add_animation_library(&"",library);attach(animator,effect)
	var scene:=PackedScene.new();assert(scene.pack(effect)==OK)
	assert(ResourceSaver.save(scene,"res://scenes/objects/effects/flamethrower_jet.tscn")==OK)
	effect.free();print("FLAME_VFX_AUTHORED");quit()
