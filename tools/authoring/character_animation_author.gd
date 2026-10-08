extends RefCounted
## Bakes motion into Godot Animation resources; used only by the authoring tool.

const FPS := 30.0
var rig: Skeleton3D
var source: Dictionary
var sources: Dictionary
var library := AnimationLibrary.new()
var names: Array[String] = []
var rests: Array[Transform3D] = []
var parents: Array[int] = []
var journal_transform := Transform3D.IDENTITY

func initialize(target: Skeleton3D, data: Dictionary, all_sources: Dictionary) -> void:
	rig = target
	source = data
	sources = all_sources
	for i in rig.get_bone_count():
		names.append(rig.get_bone_name(i))
		rests.append(rig.get_bone_global_rest(i))
		parents.append(rig.get_bone_parent(i))

func index(name: String) -> int: return names.find(name)

func global_rotation(bone: int, basis: Basis) -> void:
	if bone < 0: return
	var parent := parents[bone]
	var parent_basis := rig.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	rig.set_bone_pose_rotation(bone, (parent_basis.inverse() * basis).orthonormalized().get_rotation_quaternion())
	rig.force_update_all_bone_transforms()

func global_point(name: String) -> Vector3:
	return rig.get_bone_global_pose(index(name)).origin

func retarget(input: Dictionary, time: float, idle_arms: bool = false) -> void:
	var animation_player: AnimationPlayer = input.player
	animation_player.play(animation_player.get_animation_list()[0])
	animation_player.seek(time, true)
	animation_player.advance(0)
	animation_player.pause()
	input.rig.force_update_all_bone_transforms()
	rig.reset_bone_poses()
	var desired: Array[Basis] = []
	for i in names.size():
		var source_index: int = input.names.find(names[i])
		var basis := rests[i].basis
		var auxiliary := "Pads" in names[i] or "Pouch" in names[i] or names[i].ends_with("_end")
		if auxiliary and parents[i]>=0:
			basis = desired[parents[i]] * rig.get_bone_rest(i).basis
		elif i > 0 and source_index >= 0:
			var sampled: Basis = (Basis(Vector3.UP, PI) * input.rig.global_basis.orthonormalized() * input.rig.get_bone_global_pose(source_index).basis.orthonormalized()).orthonormalized()
			var reference: Basis = input.rests[source_index].basis
			basis = (sampled * reference.inverse() * rests[i].basis).orthonormalized()
		desired.append(basis)
		var parent := parents[i]
		rig.set_bone_pose_rotation(i, ((desired[parent].inverse() if parent >= 0 else Basis.IDENTITY) * basis).get_rotation_quaternion())
	rig.force_update_all_bone_transforms()
	if idle_arms:
		arm("Left", Vector3(-0.28, 0.88, -0.04), 0.0, false)
		arm("Right", Vector3(0.28, 0.88, -0.04), 0.0, false)
		fingers(0.20)

func two_bone(root_name: String, middle_name: String, end_name: String, target: Vector3, pole: Vector3) -> void:
	var first := index(root_name)
	var middle := index(middle_name)
	var end := index(end_name)
	if first < 0 or middle < 0 or end < 0: return
	var start := rig.get_bone_global_pose(first).origin
	var elbow := rig.get_bone_global_pose(middle).origin
	var wrist := rig.get_bone_global_pose(end).origin
	var length_a := start.distance_to(elbow)
	var length_b := elbow.distance_to(wrist)
	var direction := (target - start).normalized()
	var distance := clampf(start.distance_to(target), absf(length_a-length_b)+0.002, (length_a+length_b)*0.997)
	var bend := pole - start
	bend = (bend - direction * bend.dot(direction)).normalized()
	if bend.is_zero_approx(): bend = direction.cross(Vector3.RIGHT).normalized()
	var cosine := clampf((length_a*length_a+distance*distance-length_b*length_b)/(2.0*length_a*distance), -1, 1)
	var wanted_elbow := start + direction * length_a * cosine + bend * length_a * sqrt(maxf(0, 1-cosine*cosine))
	global_rotation(first, Basis(Quaternion((elbow-start).normalized(), (wanted_elbow-start).normalized())) * rig.get_bone_global_pose(first).basis)
	elbow = rig.get_bone_global_pose(middle).origin
	wrist = rig.get_bone_global_pose(end).origin
	global_rotation(middle, Basis(Quaternion((wrist-elbow).normalized(), (target-elbow).normalized())) * rig.get_bone_global_pose(middle).basis)

func hand_basis(side: String, pitch: float, gripping: bool) -> Basis:
	var hand := index(side+"Hand")
	var middle := index(side+"HandMiddle1")
	var finger_axis := (rests[middle].origin - rests[hand].origin).normalized()
	var desired_axis := Vector3.DOWN if gripping else Vector3.DOWN.lerp(Vector3.FORWARD, 0.18).normalized()
	var result := Basis(Quaternion(finger_axis, desired_axis)) * rests[hand].basis
	return Basis(Vector3.RIGHT, pitch) * result

func arm(side: String, target: Vector3, pitch: float, gripping: bool = true) -> void:
	var sign_value := -1.0 if side == "Left" else 1.0
	two_bone(side+"Arm", side+"ForeArm", side+"Hand", target, Vector3(sign_value*0.55, 1.03, 0.13))
	global_rotation(index(side+"Hand"), hand_basis(side, pitch, gripping))

func fingers(amount: float, trigger: bool = false) -> void:
	for i in names.size():
		if not "Hand" in names[i] or names[i].ends_with("end"): continue
		var value := amount
		if "Thumb" in names[i]: value *= 0.40
		elif "Index" in names[i] and trigger: value *= 0.46
		if names[i].ends_with("1") or names[i].ends_with("2") or names[i].ends_with("3"):
			rig.set_bone_pose_rotation(i, rig.get_bone_rest(i).basis.get_rotation_quaternion() * Quaternion(Vector3.RIGHT, value))
	rig.force_update_all_bone_transforms()

func hip_offset(offset: Vector3) -> void:
	var hips := index("Hips")
	rig.set_bone_pose_position(hips, rig.get_bone_rest(hips).origin + rig.get_bone_rest(0).basis.inverse() * offset)
	rig.force_update_all_bone_transforms()

func tilt(name: String, pitch: float, roll: float = 0.0, yaw: float = 0.0) -> void:
	var bone := index(name)
	if bone >= 0:
		global_rotation(bone, Basis.from_euler(Vector3(pitch,yaw,roll)) * rig.get_bone_global_pose(bone).basis)

func foot(side: String, target: Vector3, pitch: float = 0.0) -> void:
	var sign_value := -1.0 if side == "Left" else 1.0
	two_bone(side+"UpLeg", side+"Leg", side+"Foot", target, Vector3(sign_value*0.12, 0.48, -0.72))
	global_rotation(index(side+"Foot"), Basis(Vector3.RIGHT, pitch) * rests[index(side+"Foot")].basis)

func curve(time: float, points: Array) -> Vector3:
	for i in range(points.size()-1):
		if time <= points[i+1][0]:
			var weight: float = inverse_lerp(points[i][0], points[i+1][0], time)
			weight = smoothstep(0.0, 1.0, weight)
			return points[i][1].lerp(points[i+1][1], weight)
	return points[-1][1]

func stance(crouch: float = 0.0) -> void:
	retarget(sources.b, 1.0, true)
	hip_offset(Vector3(0,-crouch*0.62,0.07*crouch))
	tilt("Spine", -0.15*crouch)
	tilt("Spine2", -0.13*crouch)
	for side in ["Left", "Right"]:
		var sign_value := -1.0 if side == "Left" else 1.0
		foot(side, Vector3(sign_value*0.12, rests[index(side+"Foot")].origin.y, 0.01))

func gait(time: float, running: bool, direction: Vector2, crouched: bool = false) -> void:
	stance(1.0 if crouched else 0.25 if running else 0.0)
	var duration := 0.56 if running else 0.88
	if crouched: duration = 1.05
	var excursion := 0.43 if running else 0.38
	if crouched: excursion = 0.29
	var lift := 0.22 if running else 0.105
	if crouched: lift = 0.06
	var phase := fposmod(time/duration, 1.0)
	var points := [[0.0,Vector3(excursion,0,0)],[0.12,Vector3(excursion*0.60,0,0)],[0.50,Vector3(-excursion,0,0)],[0.70,Vector3(-excursion*0.15,lift,0)],[0.88,Vector3(excursion*0.85,lift*0.32,0)],[1.0,Vector3(excursion,0,0)]]
	for side in ["Left", "Right"]:
		var sign_value := -1.0 if side == "Left" else 1.0
		var p := curve(fposmod(phase + (0.5 if side == "Right" else 0),1.0),points)
		var target := Vector3(sign_value*0.12 + direction.x*p.x, rests[index(side+"Foot")].origin.y+p.y, direction.y*p.x)
		if absf(direction.x) > 0.5: target.x = sign_value * maxf(0.065, absf(target.x))
		foot(side,target,-0.24 if running and p.y>0.10 else 0.0)
		var arm_stride := p.x * (-0.32 if running else -0.23)
		arm(side, Vector3(sign_value*(0.25 if running else 0.28), (1.20 if running else 0.91), arm_stride-0.10),0.0,running)
	if running:
		tilt("Spine", -0.13)
		tilt("Spine2", -0.18)
		fingers(0.70)

func held(kind: String, pitch: float = 0.0, time: float = 0.0, first_person: bool = false) -> void:
	# The camera already follows the player's head. A world-space idle or gait
	# underneath these poses would move the shoulders a second time.
	if first_person: stance()
	else: retarget(sources.b, time, true)
	var right := Vector3(0.14,1.43,-0.23)
	var left := Vector3(-0.03,1.36,-0.35)
	if kind == "Rifle": left = Vector3(0.02,1.36,-0.415)
	elif kind == "Flashlight":
		right = Vector3(0.18,1.42,-0.29)
		left = Vector3(-0.27,0.94,-0.06)
	elif kind == "Knife":
		right = Vector3(0.24,1.25,-0.34)
		left = Vector3(-0.27,1.08,-0.12)
	elif kind == "Fuse":
		right = Vector3(0.19,1.24,-0.30)
		left = Vector3(-0.27,0.92,-0.02)
	elif kind == "Fuel":
		right = Vector3(0.38,0.94,-0.17)
		left = Vector3(-0.27,0.92,-0.02)
	elif kind == "Carry":
		right = Vector3(0.25,1.52,0.05)
		left = Vector3(-0.09,1.41,-0.07)
	if first_person and kind in ["Rifle","Pistol","Flashlight","Knife"]:
		right.z -= 0.04
		left.z -= 0.04
	if first_person:
		var breath := sin(time/3.0*TAU)*0.002
		right.y += breath
		left.y += breath
		if kind=="Fuel": right = Vector3(0.30,1.43,-0.55)
		elif kind=="Knife": right = Vector3(0.22,1.42,-0.46)
		elif kind=="Fuse": right = Vector3(0.20,1.42,-0.40)
	var pivot := Vector3(0,1.49,0)
	var turn := Basis(Vector3.RIGHT, pitch)
	right = pivot + turn*(right-pivot)
	left = pivot + turn*(left-pivot)
	tilt("Spine2", pitch*0.18)
	tilt("Head", pitch*0.25)
	arm("Right",right,pitch)
	arm("Left",left,pitch,kind in ["Rifle","Pistol","Carry"])
	fingers(1.12,kind in ["Rifle","Pistol"])

func carry_action(time: float, placing: bool, first_person: bool) -> void:
	var phase := clampf(time/(1.8 if placing else 1.6),0,1)
	stance(curve(phase,[[0.0,Vector3.ZERO],[0.30,Vector3(0.28 if placing else 0.75,0,0)],[0.60,Vector3(0.22 if placing else 0.42,0,0)],[1.0,Vector3.ZERO]]).x)
	var right_points := [[0.0,Vector3(0.25,1.52,0.05)],[0.55,Vector3(0.28,1.08,-0.48)],[1.0,Vector3(0.28,0.88,-0.04)]] if placing else [[0.0,Vector3(0.28,0.88,-0.04)],[0.30,Vector3(0.22,0.55,-0.38)],[0.75,Vector3(0.25,1.42,-0.12)],[1.0,Vector3(0.25,1.52,0.05)]]
	var left_points := [[0.0,Vector3(-0.09,1.41,-0.07)],[0.55,Vector3(-0.12,1.08,-0.48)],[1.0,Vector3(-0.28,0.88,-0.04)]] if placing else [[0.0,Vector3(-0.28,0.88,-0.04)],[0.30,Vector3(-0.15,0.55,-0.40)],[0.75,Vector3(-0.09,1.32,-0.18)],[1.0,Vector3(-0.09,1.41,-0.07)]]
	arm("Right",curve(phase,right_points),0)
	arm("Left",curve(phase,left_points),0)
	fingers(0.65)

func journal(time: float, duration: float, closing: bool = false, first_person: bool = false) -> void:
	stance()
	var fraction := clampf(time/duration,0,1)
	if closing: fraction = 1-fraction
	var point := curve(fraction,[[0.0,Vector3(0.16,1.08,-0.21)],[0.4,Vector3(0.13,1.31,-0.34)],[1.0,Vector3(0.10,1.48,-0.44)]])
	if first_person: point.y+=0.04
	journal_transform = Transform3D(Basis(Vector3.RIGHT,-0.30),point)
	var opening := smoothstep(0.28,0.95,fraction)
	var cover := journal_transform*Transform3D(Basis(Vector3.UP,-PI*opening),Vector3(-0.105,0,0.008))
	journal_hands(journal_transform,cover)
	tilt("Head",-0.25*fraction)

func journal_hands(book: Transform3D, cover: Transform3D) -> void:
	for side in ["Left","Right"]:
		var frame := cover if side=="Left" else book
		var point := Vector3(0.19,-0.245,-0.045) if side=="Left" else Vector3(0.08,-0.245,0.045)
		arm(side,frame*point,0.0)
		var hand := index(side+"Hand")
		var source_y := (rests[index(side+"HandMiddle1")].origin-rests[hand].origin).normalized()
		var source_x := rests[hand].basis.x
		source_x = (source_x-source_y*source_x.dot(source_y)).normalized()
		var y := book.basis.y.normalized()
		var x := -book.basis.x.normalized()
		var rotation := Basis(x,y,x.cross(y))*Basis(source_x,source_y,source_x.cross(source_y)).inverse()
		global_rotation(hand,rotation*rests[hand].basis)
	fingers(0.60)

func journal_view(time: float, ui: Node) -> void:
	stance()
	var clip: Animation = ui.get_node("PresentationAnimation").get_animation("open")
	# Sample the editable book asset directly. A disabled SubViewport does not
	# reliably flush its transform caches while baking hundreds of keys.
	var frame := Transform3D(Basis.from_euler(clip.value_track_interpolate(1,time))*Basis.from_scale(clip.value_track_interpolate(5,time)),clip.value_track_interpolate(0,time))
	var cover := frame*Transform3D(Basis(Vector3.UP,clip.bezier_track_interpolate(6,time)),Vector3(-0.105,0,0.008))
	frame.origin.y += 1.65
	cover.origin.y += 1.65
	journal_hands(frame,cover)

func add_clip(name: String, length: float, loop: bool, sampler: Callable) -> void:
	var clip := Animation.new()
	clip.length = length
	clip.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var rotations: Array[int] = []
	var positions: Array[int] = []
	var journal_position := -1
	var journal_rotation := -1
	if name in ["JournalOpen","JournalReading","JournalClose"]:
		journal_position = clip.add_track(Animation.TYPE_POSITION_3D)
		journal_rotation = clip.add_track(Animation.TYPE_ROTATION_3D)
		for track in [journal_position,journal_rotation]: clip.track_set_path(track,NodePath("Skeleton3D/RightHand/Equipment/Journal"))
	for i in names.size():
		var path := NodePath("Skeleton3D:"+names[i])
		var rotation_track := clip.add_track(Animation.TYPE_ROTATION_3D)
		clip.track_set_path(rotation_track,path)
		rotations.append(rotation_track)
		var position_track := clip.add_track(Animation.TYPE_POSITION_3D)
		clip.track_set_path(position_track,path)
		positions.append(position_track)
	var frames := maxi(2,ceili(length*FPS))
	for frame in range(frames+1):
		var time := minf(length,float(frame)*length/frames)
		sampler.call(0.0 if loop and frame==frames else time)
		if journal_position>=0:
			var socket := rig.get_bone_global_pose(index("RightHand"))*Transform3D(hand_basis("Right",0,true).inverse(),Vector3.ZERO)
			var local := socket.affine_inverse()*journal_transform
			clip.position_track_insert_key(journal_position,time,local.origin)
			clip.rotation_track_insert_key(journal_rotation,time,local.basis.get_rotation_quaternion())
		for i in names.size():
			clip.rotation_track_insert_key(rotations[i],time,rig.get_bone_pose_rotation(i).normalized())
			clip.position_track_insert_key(positions[i],time,rig.get_bone_pose_position(i))
	# Static translations remain rest data, not hundreds of redundant keys.
	for track in range(clip.get_track_count()-1,-1,-1):
		if clip.track_get_type(track) == Animation.TYPE_POSITION_3D:
			var first: Vector3 = clip.track_get_key_value(track,0)
			var constant := true
			for key in clip.track_get_key_count(track): constant = constant and first.is_equal_approx(clip.track_get_key_value(track,key))
			if constant:
				for key in range(clip.track_get_key_count(track)-1,0,-1): clip.track_remove_key(track,key)
	for track in rotations:
		var first: Quaternion = clip.track_get_key_value(track,0)
		var constant := true
		for key in clip.track_get_key_count(track):
			var value: Quaternion = clip.track_get_key_value(track,key)
			constant = constant and absf(first.dot(value))>0.9999999
		if constant:
			for key in range(clip.track_get_key_count(track)-1,0,-1): clip.track_remove_key(track,key)
	if name in ["JournalOpen","JournalReading","JournalClose"]:
		var cover := clip.add_track(Animation.TYPE_ROTATION_3D)
		clip.track_set_path(cover,NodePath("Skeleton3D/RightHand/Equipment/Journal/FrontCoverPivot"))
		var binding := clip.add_track(Animation.TYPE_ROTATION_3D)
		clip.track_set_path(binding,NodePath("Skeleton3D/RightHand/Equipment/Journal/PaperBindingRig:CoverFold"))
		for key in range(ceili(length*FPS)+1):
			var time := minf(length,key/FPS)
			var opened := 1.0 if name=="JournalReading" else smoothstep(0.32,1.20,time) if name=="JournalOpen" else 1-smoothstep(0.12,length,time)
			var rotation := Quaternion(Vector3.UP,-PI*opened)
			clip.rotation_track_insert_key(cover,time,rotation)
			clip.rotation_track_insert_key(binding,time,rotation)
	library.add_animation(name,clip)

func build(first_person: bool = false) -> AnimationLibrary:
	add_clip("Idle",sources.b.clip.length,true,func(t): retarget(sources.b,t,true))
	add_clip("WalkForward",0.88,true,func(t): retarget(sources.a,t/0.88*sources.a.clip.length))
	for direction in ["Backward","Left","Right"]:
		var vector := Vector2(0,1) if direction=="Backward" else Vector2(-1,0) if direction=="Left" else Vector2(1,0)
		add_clip("Walk"+direction,0.88,true,func(t): gait(t,false,vector))
	for direction in ["Forward","Backward","Left","Right"]:
		var vector := Vector2(0,-1) if direction=="Forward" else Vector2(0,1) if direction=="Backward" else Vector2(-1,0) if direction=="Left" else Vector2(1,0)
		add_clip("Run"+direction,0.56,true,func(t): gait(t,true,vector))
		add_clip("Crouch"+direction,1.05,true,func(t): gait(t,false,vector,true))
	add_clip("CrouchIdle",3.0,true,func(t): stance(1.0); tilt("Spine2",curve(t/3,[[0.0,Vector3.ZERO],[0.5,Vector3(0.008,0,0)],[1.0,Vector3.ZERO]]).x))
	add_clip("CrouchEnter",0.32,false,func(t): stance(smoothstep(0,0.32,t)))
	add_clip("CrouchExit",0.32,false,func(t): stance(1-smoothstep(0,0.32,t)))
	add_clip("JumpStart",0.15,false,func(t): stance(); hip_offset(curve(t/0.15,[[0.0,Vector3(0,-0.09,0)],[0.45,Vector3(0,-0.035,0)],[1.0,Vector3(0,0.045,0)]])); tilt("Spine2",-0.12))
	add_clip("InAir",0.80,true,func(t): stance(); hip_offset(Vector3(0,-0.03,0)); foot("Left",Vector3(-0.12,0.30,-0.12),-0.2); foot("Right",Vector3(0.12,0.26,0.08),0.05); arm("Left",Vector3(-0.31,1.09,-0.18),0,false); arm("Right",Vector3(0.31,1.08,-0.08),0,false))
	add_clip("Landing",0.33,false,func(t): stance(sin(clampf(t/0.33,0,1)*PI)*0.30))
	for kind in ["Rifle","Pistol","Knife","Flashlight","Fuse","Fuel","Carry"]:
		for aim in [-1,0,1]:
			add_clip(kind+"Aim"+str(aim),3.0,true,func(t): held(kind,aim*1.25,t,first_person))
	add_clip("JournalOpen",1.85,false,func(t): journal(t,1.25,false,first_person))
	add_clip("JournalReading",3.0,true,func(t): journal(1.85,1.85,false,first_person))
	add_clip("JournalClose",0.92,false,func(t): journal(t,0.92,true,first_person))
	add_clip("CarryPickup",1.6,false,func(t): carry_action(t,false,first_person))
	add_clip("CarryPlace",1.8,false,func(t): carry_action(t,true,first_person))
	add_clip("Vehicle",3.0,true,func(t): stance(0.65); foot("Left",Vector3(-0.28,0.20,-0.45)); foot("Right",Vector3(0.28,0.20,-0.45)); arm("Left",Vector3(-0.30,0.94,-0.78),0); arm("Right",Vector3(0.30,0.94,-0.78),0); fingers(1.0))
	add_clip("Sleep",3.0,true,func(t): stance(); global_rotation(0,Basis(Vector3.RIGHT,-PI*0.5)); rig.set_bone_pose_position(0,Vector3(0,0.18,0.43)); rig.force_update_all_bone_transforms())
	add_clip("Death",0.18,false,func(t): stance(); tilt("Spine2",0.18*smoothstep(0,0.18,t)))
	for label in ["Forward","Backward","Left","Right","Neutral"]:
		var pitch := -0.08 if label=="Forward" else 0.06 if label=="Backward" else 0.0
		var roll := 0.065 if label=="Left" else -0.065 if label=="Right" else 0.0
		add_clip("Lean"+label,1.0,true,func(t): rig.reset_bone_poses(); tilt("Spine",pitch,roll); tilt("Spine2",pitch*0.6,roll*0.45))
	for label in ["Left","Right"]:
		var angle := 0.13 if label=="Left" else -0.13
		add_clip("Turn"+label,0.5,false,func(t): stance(); tilt("Hips",0,0,angle*smoothstep(0,0.5,t)); tilt("Spine2",0,0,-angle*0.60); foot(label,rests[index(label+"Foot")].origin+curve(t/0.5,[[0.0,Vector3.ZERO],[0.35,Vector3(0,0.08,0)],[1.0,Vector3.ZERO]])))
	add_clip("KnifeAttack",0.42,false,func(t): held("Knife",0,0,first_person); arm("Right",curve(t/0.42,[[0.0,Vector3(0.22,1.42,-0.46) if first_person else Vector3(0.24,1.25,-0.34)],[0.25,Vector3(0.32,1.56 if first_person else 1.40,-0.20)],[0.60,Vector3(0.09,1.40 if first_person else 1.28,-0.62 if first_person else -0.54)],[1.0,Vector3(0.22,1.42,-0.46) if first_person else Vector3(0.24,1.25,-0.34)]]),curve(t/0.42,[[0.0,Vector3.ZERO],[0.6,Vector3(-0.35,0,0)],[1.0,Vector3.ZERO]]).x); fingers(1.12))
	for kind in ["Rifle","Pistol"]:
		add_clip(kind+"Recoil",0.16,false,func(t): rig.reset_bone_poses(); tilt("RightHand",curve(t/0.16,[[0.0,Vector3.ZERO],[0.18,Vector3(0.065,0,0)],[1.0,Vector3.ZERO]]).x); tilt("RightForeArm",curve(t/0.16,[[0.0,Vector3.ZERO],[0.18,Vector3(0.025,0,0)],[1.0,Vector3.ZERO]]).x))
		var reload_length := 2.1 if kind=="Rifle" else 1.35
		add_clip(kind+"Reload",reload_length,false,func(t): held(kind,0,0,first_person); arm("Left",curve(t/reload_length,[[0.0,Vector3(-0.10,1.34,-0.60)],[0.18,Vector3(-0.04,1.18,-0.28)],[0.45,Vector3(-0.10,0.96,-0.14)],[0.72,Vector3(-0.02,1.20,-0.27)],[1.0,Vector3(-0.10,1.34,-0.60)]]),0,true); fingers(0.9))
	for kind in ["Rifle","Pistol","Flashlight"]:
		add_clip(kind+"Battery",0.97,false,func(t): held(kind,0,0,first_person); arm("Left",curve(t/0.97,[[0.0,Vector3(-0.27,0.94,-0.06)],[0.22,Vector3(-0.10,1.05,-0.12)],[0.55,Vector3(0.13,1.34,-0.27)],[0.82,Vector3(0.13,1.34,-0.27)],[1.0,Vector3(-0.27,0.94,-0.06)]]),0,true); fingers(0.65))
	return library

func clip_node(name: String) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = name
	return node

func locomotion(crouch: bool = false) -> AnimationNodeBlendSpace2D:
	var space := AnimationNodeBlendSpace2D.new()
	space.min_space = Vector2(-7,-7)
	space.max_space = Vector2(7,7)
	space.blend_mode = AnimationNodeBlendSpace2D.BLEND_MODE_INTERPOLATED
	space.add_blend_point(clip_node("CrouchIdle" if crouch else "Idle"),Vector2.ZERO)
	var speed := 2.2 if crouch else 4.0
	for direction in ["Forward","Backward","Left","Right"]:
		var vector := Vector2(0,-1) if direction=="Forward" else Vector2(0,1) if direction=="Backward" else Vector2(-1,0) if direction=="Left" else Vector2(1,0)
		space.add_blend_point(clip_node(("Crouch" if crouch else "Walk")+direction),vector*speed)
		if not crouch: space.add_blend_point(clip_node("Run"+direction),vector*6.8)
	return space

func upper_filter(node: AnimationNode, first_person: bool = false) -> void:
	node.filter_enabled = true
	for name in names:
		if first_person or (not name in ["Root","Hips"] and not "Leg" in name and not "Foot" in name and not "Toe" in name and not "Knee" in name and not "Pouch" in name):
			node.set_filter_path(NodePath("Skeleton3D:"+name),true)

func graph(first_person: bool = false) -> AnimationNodeBlendTree:
	var tree := AnimationNodeBlendTree.new()
	var states := AnimationNodeStateMachine.new()
	for label in ["Stand","Crouch"]:
		var ground := AnimationNodeBlendTree.new()
		ground.add_node("Locomotion",locomotion(label=="Crouch"))
		ground.add_node("StrideRate",AnimationNodeTimeScale.new())
		ground.connect_node("StrideRate",0,"Locomotion")
		ground.connect_node("output",0,"StrideRate")
		states.add_node(label,ground)
	for state in ["CrouchEnter","CrouchExit","JumpStart","InAir","Landing","TurnLeft","TurnRight","JournalOpen","JournalReading","JournalClose","Death","Vehicle","Sleep"]:
		states.add_node(state,clip_node(state))
	for state in ["CarryPickup","CarryPlace"]:
		var action := AnimationNodeBlendTree.new()
		action.add_node("Pose",clip_node(state))
		action.add_node("ActionTime",AnimationNodeTimeSeek.new())
		action.connect_node("ActionTime",0,"Pose")
		action.connect_node("output",0,"ActionTime")
		states.add_node(state,action)
	var all_states := ["Stand","Crouch","CrouchEnter","CrouchExit","JumpStart","InAir","Landing","TurnLeft","TurnRight","JournalOpen","JournalReading","JournalClose","Death","Vehicle","Sleep","CarryPickup","CarryPlace"]
	var automatic := {"CrouchEnter":"Crouch","CrouchExit":"Stand","JumpStart":"InAir","Landing":"Stand","TurnLeft":"Stand","TurnRight":"Stand","JournalOpen":"JournalReading","JournalClose":"Stand"}
	for from_state in all_states:
		for to_state in all_states:
			if from_state == to_state: continue
			var transition := AnimationNodeStateMachineTransition.new()
			transition.xfade_time = 0.16
			if automatic.get(from_state,"") == to_state:
				transition.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
				transition.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
			states.add_transition(from_state,to_state,transition)
	var start := AnimationNodeStateMachineTransition.new()
	start.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	states.add_transition("Start","Stand",start)
	tree.add_node("Movement",states,Vector2(0,0))
	var choice := AnimationNodeTransition.new()
	choice.set("input_count",7)
	choice.xfade_time = 0.18
	var input_index := 0
	for kind in ["Rifle","Pistol","Knife","Flashlight","Fuse","Fuel","Carry"]:
		choice.set("input_%d/name"%input_index,kind)
		var aim := AnimationNodeBlendSpace1D.new()
		aim.min_space = -1.25
		aim.max_space = 1.25
		for point in [-1,0,1]: aim.add_blend_point(clip_node(kind+"Aim"+str(point)),point*1.25)
		tree.add_node(kind,aim,Vector2(0,100+input_index*70))
		input_index += 1
	tree.add_node("Equipment",choice,Vector2(300,200))
	input_index = 0
	for kind in ["Rifle","Pistol","Knife","Flashlight","Fuse","Fuel","Carry"]:
		tree.connect_node("Equipment",input_index,kind)
		input_index += 1
	var upper := AnimationNodeBlend2.new()
	upper_filter(upper,first_person)
	tree.add_node("UpperBody",upper,Vector2(600,0))
	tree.connect_node("UpperBody",0,"Movement")
	tree.connect_node("UpperBody",1,"Equipment")
	var lean := AnimationNodeBlendSpace2D.new()
	lean.min_space = Vector2(-1,-1); lean.max_space = Vector2(1,1)
	lean.add_blend_point(clip_node("LeanNeutral"),Vector2.ZERO)
	lean.add_blend_point(clip_node("LeanForward"),Vector2(0,-1))
	lean.add_blend_point(clip_node("LeanBackward"),Vector2(0,1))
	lean.add_blend_point(clip_node("LeanLeft"),Vector2(-1,0))
	lean.add_blend_point(clip_node("LeanRight"),Vector2(1,0))
	tree.add_node("Lean",lean,Vector2(600,300))
	var inertia := AnimationNodeAdd2.new()
	inertia.filter_enabled = true
	for name in ["Spine","Spine1","Spine2"]: inertia.set_filter_path(NodePath("Skeleton3D:"+name),true)
	tree.add_node("Inertia",inertia,Vector2(900,0))
	tree.connect_node("Inertia",0,"UpperBody")
	tree.connect_node("Inertia",1,"Lean")
	var action := AnimationNodeTransition.new()
	var actions := ["RifleReload","RifleBattery","PistolReload","PistolBattery","FlashlightBattery","KnifeAttack"]
	action.set("input_count",actions.size())
	input_index = 0
	for name in actions:
		action.set("input_%d/name"%input_index,name)
		tree.add_node(name,clip_node(name),Vector2(900,150+input_index*70))
		input_index += 1
	tree.add_node("Action",action,Vector2(1150,250))
	input_index = 0
	for name in actions:
		tree.connect_node("Action",input_index,name)
		input_index += 1
	var one_shot := AnimationNodeOneShot.new()
	one_shot.fadein_time = 0.04
	one_shot.fadeout_time = 0.13
	upper_filter(one_shot,first_person)
	tree.add_node("Handling",one_shot,Vector2(1400,0))
	var recoil := AnimationNodeTransition.new()
	recoil.set("input_count",2)
	input_index = 0
	for kind in ["Rifle","Pistol"]:
		recoil.set("input_%d/name"%input_index,kind)
		tree.add_node(kind+"Recoil",clip_node(kind+"Recoil"))
		input_index += 1
	tree.add_node("Recoil",recoil)
	input_index = 0
	for kind in ["Rifle","Pistol"]:
		tree.connect_node("Recoil",input_index,kind+"Recoil")
		input_index += 1
	var kick := AnimationNodeOneShot.new()
	kick.mix_mode = AnimationNodeOneShot.MIX_MODE_ADD
	kick.fadein_time = 0.01
	kick.fadeout_time = 0.04
	upper_filter(kick)
	tree.add_node("Kick",kick)
	tree.connect_node("Kick",0,"Inertia")
	tree.connect_node("Kick",1,"Recoil")
	tree.connect_node("Handling",0,"Kick")
	tree.connect_node("Handling",1,"Action")
	tree.connect_node("output",0,"Handling")
	return tree
