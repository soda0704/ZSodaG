extends "res://tools/authoring/character_animation_author.gd"
## Offline pose authoring. The game only plays the saved Animation assets.
## Frames use measured wrist/knuckle anatomy, not an assumed bone Euler axis.

const GRIPS := {
	"Pistol": Vector3(0.035,-0.085,0.130),
	"Rifle": Vector3(0.036,-0.090,0.150),
	"Flashlight": Vector3(0.040,0.100,-0.220),
}
const SUPPORTS := {
	"Pistol": Vector3(-0.035,-0.083,0.140),
	"Rifle": Vector3(-0.045,-0.055,-0.160),
}
var fp_authoring := false
const FP_LEFT_ANCHOR := Vector3(-0.22,1.46,-0.14)
var previous_sample: Dictionary = {}

func add_clip(name: String, length: float, loop: bool, sampler: Callable) -> void:
	previous_sample.clear()
	super.add_clip(name,length,loop,sampler)
	if not name.begins_with("Journal"): return
	var clip := library.get_animation(name)
	for track in range(clip.get_track_count()-1,-1,-1):
		var old := String(clip.track_get_path(track))
		if not old.begins_with("Skeleton3D/RightHand/Equipment/Journal"): continue
		if old=="Skeleton3D/RightHand/Equipment/Journal": clip.remove_track(track)
		else: clip.track_set_path(track,NodePath(old.replace("Skeleton3D/RightHand/Equipment/Journal","Journal")))
	# The old wrist-relative track was constant and its redundant keys had been
	# removed. Author new independent book tracks, including the entire lift arc.
	var position_track:=clip.add_track(Animation.TYPE_POSITION_3D)
	var rotation_track:=clip.add_track(Animation.TYPE_ROTATION_3D)
	clip.track_set_path(position_track,NodePath("Journal")); clip.track_set_path(rotation_track,NodePath("Journal"))
	var frames:=maxi(2,ceili(length*FPS))
	for key in frames+1:
		var t:=float(key)*length/frames
		var phase:=0.88 if name=="JournalReading" else 0.88*(1-t/length) if name=="JournalClose" else t/length*0.88
		var frame:=journal_frame(phase,fp_authoring)
		clip.position_track_insert_key(position_track,t,frame.origin)
		clip.rotation_track_insert_key(rotation_track,t,frame.basis.orthonormalized().get_rotation_quaternion())
	for track in clip.get_track_count():
		if String(clip.track_get_path(track)) in ["Journal/FrontCoverPivot","Journal/PaperBindingRig:CoverFold"]:
			for key in clip.track_get_key_count(track):
				var t := clip.track_get_key_time(track,key)
				var u := 1.0 if name=="JournalReading" else smoothstep(0.18,0.84,t/length) if name=="JournalOpen" else 1-smoothstep(0.05,0.76,t/length)
				clip.track_set_key_value(track,key,Quaternion(Vector3.UP,-PI*u))

func finish_sample() -> void:
	if not fp_authoring:
		super.finish_sample()
		return
	# The long reference view rigs cross elbow pole singularities while being
	# fitted to our shorter sleeves. Bake continuous joints across those keys.
	# This remains an Animation asset; no per-frame runtime bone edits.
	for side in ["Left","Right"]:
		for role in ["Arm","ForeArm","Hand"]:
			var bone:=index(side+role); var q:=rig.get_bone_pose_rotation(bone)
			if previous_sample.has(bone):
				var distance: float=previous_sample[bone].angle_to(q)
				if distance>deg_to_rad(16):q=previous_sample[bone].slerp(q,deg_to_rad(16)/distance)
			rig.set_bone_pose_rotation(bone,q)
			previous_sample[bone]=q
	rig.force_update_all_bone_transforms()

func anatomical_frame(side: String) -> Basis:
	var wrist := rests[index(side+"Hand")].origin
	var y := (rests[index(side+"HandMiddle1")].origin-wrist).normalized()
	var x := rests[index(side+"HandIndex1")].origin-rests[index(side+"HandPinky1")].origin
	x *= 1.0 if side=="Right" else -1.0
	x = (x-y*x.dot(y)).normalized()
	return Basis(x,y,x.cross(y)).orthonormalized()

func palm_basis(side: String, distal: Vector3, normal: Vector3) -> Basis:
	var y := distal.normalized()
	var z := (normal-y*normal.dot(y)).normalized()
	var frame := Basis(y.cross(z),y,z)
	return (frame*anatomical_frame(side).inverse()*rests[index(side+"Hand")].basis).orthonormalized()

func hand_basis(side: String, pitch: float, gripping: bool) -> Basis:
	var distal:=Vector3(-0.18 if side=="Right" else 0.18,0.40,-0.90).normalized() if gripping else Vector3(0,-0.96,-0.28)
	return Basis(Vector3.RIGHT,pitch)*palm_basis(side,distal,Vector3.LEFT if side=="Right" else Vector3.RIGHT)

var reference_motion: Dictionary = {}

func motion(label: String, clip: String, time: float) -> Dictionary:
	if not reference_motion.has(label):
		reference_motion[label] = JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/pose_sources/"+label+".json"))
	var data: Dictionary = reference_motion[label][clip]
	var sample := clampf(time/float(data.duration),0,1)*float(data.frames.size()-1)
	return data.frames[mini(int(round(sample)),data.frames.size()-1)]

func reference_fingers(side: String, data: Dictionary) -> void:
	var wrist := index(side+"Hand")
	var frame := rig.get_bone_global_pose(wrist).basis*rests[wrist].basis.inverse()*anatomical_frame(side)
	for finger in ["Thumb","Index","Middle","Ring","Pinky"]:
		for segment in [1,2,3]:
			var bone := index(side+"Hand"+finger+str(segment))
			var end := index(side+"Hand"+finger+str(segment+1))
			if bone<0 or end<0: continue
			var values: Array = data.fingers[finger][segment-1]
			var reference_direction := Vector3(values[0],values[1],values[2]).normalized()
			if finger!="Thumb":
				# Transfer joint flexion, not a foreign bone's axial orientation.
				# The reference has extra metacarpals/twist bones; our native rig
				# must keep PIP/DIP motion in the proximal finger's hinge plane.
				var cumulative := 0.0; var previous := 0.0
				for joint in segment:
					var value: Array=data.fingers[finger][joint]
					var raw:=atan2(float(value[2]),float(value[1]))
					cumulative+=clampf(raw-previous,0.0,deg_to_rad(78 if joint==0 else 100 if joint==1 else 68))
					previous=raw
				var first: Array=data.fingers[finger][0]
				var spread:=clampf(asin(clampf(float(first[0]),-1,1)),deg_to_rad(-10),deg_to_rad(10))
				reference_direction=Vector3(sin(spread),cos(cumulative)*cos(spread),sin(cumulative)*cos(spread))
			var direction := frame*reference_direction
			var current := (global_point(names[end])-global_point(names[bone])).normalized()
			global_rotation(bone,Basis(Quaternion(current,direction))*rig.get_bone_global_pose(bone).basis)

func pose_hand(side: String, label: String) -> void:
	if label in ["Pistol_Right","Pistol_Left","Rifle_Right","Rifle_LeftSupport","Knife_Right"]:
		var source_label := "rifle" if label.begins_with("Rifle") else "knife_pose" if label.begins_with("Knife") else "pistol"
		var clip := "Fire" if source_label=="rifle" else "Armature|Idle" if source_label=="knife_pose" else "Armature|Shoot"
		var reference:Dictionary=motion(source_label,clip,0)[side].duplicate(true)
		if label=="Pistol_Left" and side=="Left":
			# The supporting palm wraps the shooting hand, a wider object than
			# the reference pistol grip. Fit flexion to that contact surface.
			for finger in ["Index","Middle","Ring","Pinky"]:
				var angle:=0.0
				for joint in 3:
					angle += [0.85,1.15,0.65][joint]
					reference.fingers[finger][joint]=[0.0,cos(angle),sin(angle)]
		reference_fingers(side,reference)
		return
	# Only the non-rigged book / cylindrical props require authored flexion.
	# Bends are measured in the palm frame; the thumb has its own opposition.
	var wrist := index(side+"Hand")
	var frame := rig.get_bone_global_pose(wrist).basis*rests[wrist].basis.inverse()*anatomical_frame(side)
	var angles: Array = [0.15,0.26,0.36] if label=="Relaxed" else [0.52,1.45,2.08] if label=="Flashlight" else [0.30,0.80,1.28]
	for finger in ["Index","Middle","Ring","Pinky"]:
		for segment in [1,2,3]:
			var bone := index(side+"Hand"+finger+str(segment)); var end := index(side+"Hand"+finger+str(segment+1))
			if bone<0 or end<0: continue
			var direction := frame*Vector3(0,cos(angles[segment-1]),sin(angles[segment-1]))
			var current := (global_point(names[end])-global_point(names[bone])).normalized()
			global_rotation(bone,Basis(Quaternion(current,direction))*rig.get_bone_global_pose(bone).basis)
	for segment in [1,2,3]:
		var bone := index(side+"HandThumb"+str(segment)); var end := index(side+"HandThumb"+str(segment+1))
		if bone<0 or end<0: continue
		var sign_x := 1.0 if side=="Right" else -1.0
		var direction := frame*Vector3(sign_x*0.55,0.72,0.42).normalized()
		var current := (global_point(names[end])-global_point(names[bone])).normalized()
		global_rotation(bone,Basis(Quaternion(current,direction))*rig.get_bone_global_pose(bone).basis)

func global_rotation(bone: int, basis: Basis) -> void:
	if bone>=0 and names[bone] in ["LeftHand","RightHand"]:
		anatomical_wrist("Left" if names[bone]=="LeftHand" else "Right",basis)
	else: super.global_rotation(bone,basis)

func anatomical_wrist(side: String, desired: Basis) -> void:
	var forearm := index(side+"ForeArm"); var hand := index(side+"Hand")
	var forearm_pose := rig.get_bone_global_pose(forearm)
	var neutral := forearm_pose.basis*rests[forearm].basis.inverse()*rests[hand].basis
	var axis := (global_point(side+"Hand")-forearm_pose.origin).normalized()
	var q := (desired*neutral.inverse()).orthonormalized().get_rotation_quaternion()
	if q.w<0: q=-q
	var projection := Vector3(q.x,q.y,q.z).dot(axis)
	var twist := 2*atan2(projection,q.w)
	# Pronation belongs to the forearm. It must never be collapsed into the
	# hand joint. The twist is baked into the native clip, not a runtime hack.
	var desired_hand := desired
	var forearm_basis := Basis(axis,twist)*forearm_pose.basis
	var upper := index(side+"Arm")
	var forearm_neutral := rig.get_bone_global_pose(upper).basis*rests[upper].basis.inverse()*rests[forearm].basis
	var elbow_q := (forearm_basis*forearm_neutral.inverse()).orthonormalized().get_rotation_quaternion()
	if elbow_q.w<0: elbow_q=-elbow_q
	var pronation := 2*atan2(Vector3(elbow_q.x,elbow_q.y,elbow_q.z).dot(axis),elbow_q.w)
	var correction := clampf(pronation,deg_to_rad(-80),deg_to_rad(80))-pronation
	forearm_basis=Basis(axis,correction)*forearm_basis
	desired_hand=Basis(axis,correction)*desired_hand
	super.global_rotation(forearm,forearm_basis)
	neutral = rig.get_bone_global_pose(forearm).basis*rests[forearm].basis.inverse()*rests[hand].basis
	var flexion := (neutral.inverse()*desired_hand).orthonormalized().get_rotation_quaternion()
	if flexion.w<0: flexion=-flexion
	var bend := flexion.get_angle()
	if bend>deg_to_rad(48): flexion=Quaternion.IDENTITY.slerp(flexion,deg_to_rad(48)/bend)
	super.global_rotation(hand,neutral*Basis(flexion))

func arm(side: String, target: Vector3, pitch: float, gripping: bool = true) -> void:
	# Reconstruct an elbow hinge frame before pronation. Merely swinging the
	# A-pose bones leaves an arbitrary roll, which the old wrist then absorbed.
	var upper := index(side+"Arm"); var forearm := index(side+"ForeArm"); var hand := index(side+"Hand")
	for bone in [upper,forearm,hand]: rig.set_bone_pose_rotation(bone,rig.get_bone_rest(bone).basis.get_rotation_quaternion())
	rig.force_update_all_bone_transforms()
	var sign_x := -1.0 if side=="Left" else 1.0
	two_bone(side+"Arm",side+"ForeArm",side+"Hand",target,Vector3(sign_x*0.42,1.03,0.08))
	var u := (global_point(side+"ForeArm")-global_point(side+"Arm")).normalized()
	var f := (global_point(side+"Hand")-global_point(side+"ForeArm")).normalized()
	var rest_palm := anatomical_frame(side).x
	# The transverse knuckle axis identifies the elbow hinge axis.
	# Preserve that anatomical plane instead of letting IK choose axial roll.
	var plane := u.cross(f).normalized()
	var current := rig.get_bone_global_pose(upper).basis*rests[upper].basis.inverse()*rest_palm
	current=(current-u*current.dot(u)).normalized()
	var wanted := plane
	var roll := atan2(u.dot(current.cross(wanted)),current.dot(wanted))
	var elbow_basis := Basis(u,roll)*rig.get_bone_global_pose(upper).basis
	# Roll the humerus, then re-align the forearm without moving the elbow.
	super.global_rotation(upper,elbow_basis)
	var actual := (global_point(side+"Hand")-global_point(side+"ForeArm")).normalized()
	super.global_rotation(forearm,Basis(Quaternion(actual,f))*rig.get_bone_global_pose(forearm).basis)
	anatomical_wrist(side,hand_basis(side,pitch,gripping))

func fingers(amount: float, trigger: bool = false) -> void:
	for side in ["Left","Right"]:
		pose_hand(side,"Pistol_Right" if side=="Right" and trigger else "Relaxed" if amount<0.35 else "Pistol_Left")

func support_basis(kind: String) -> Basis:
	return palm_basis("Left",Vector3(0.20,0.35,-0.91) if kind=="Rifle" else Vector3(0,0.40,-0.92),Vector3.RIGHT)

func held(kind: String, pitch: float = 0.0, time: float = 0.0, first_person: bool = false) -> void:
	fp_stance() if first_person else retarget(sources.b,time,true)
	var right := Vector3(0.14,1.37,-0.30)
	if first_person: right = Vector3(0.13,1.45,-0.39)
	if kind=="Rifle": right = Vector3(0.13,1.43,-0.37) if first_person else Vector3(0.16,1.34,-0.18)
	elif kind=="Flashlight": right = Vector3(0.20,1.47,-0.38) if first_person else Vector3(0.21,1.35,-0.28)
	elif kind=="Knife": right = Vector3(0.23,1.40,-0.43) if first_person else Vector3(0.24,1.25,-0.34)
	elif kind=="Fuse": right = Vector3(0.20,1.41,-0.40) if first_person else Vector3(0.19,1.24,-0.30)
	elif kind=="Fuel": right = Vector3(0.30,1.36,-0.54) if first_person else Vector3(0.38,0.94,-0.17)
	elif kind=="Carry": right = Vector3(0.25,1.52,0.05)
	if first_person: right.y += sin(time/3.0*TAU)*0.0015
	var turn := Basis(Vector3.RIGHT,clampf(pitch,-0.62,0.62))
	var pivot := Vector3(0,1.40,0)
	right = pivot+turn*(right-pivot)
	arm("Right",right,clampf(pitch,-0.62,0.62),kind!="Fuel")
	var left := Vector3(-0.28,1.03,-0.14) if first_person else Vector3(-0.27,0.94,-0.06)
	if SUPPORTS.has(kind):
		left = right+turn*(SUPPORTS[kind]-GRIPS[kind])
		arm("Left",left,0)
		global_rotation(index("LeftHand"),turn*support_basis(kind))
	else: arm("Left",left,0,false)
	pose_hand("Right",kind+"_Right" if kind in ["Pistol","Rifle","Knife"] else "Flashlight" if kind=="Flashlight" else "Pistol_Left")
	pose_hand("Left","Rifle_LeftSupport" if kind=="Rifle" else "Pistol_Left" if kind=="Pistol" else "Relaxed")
	if not first_person:
		tilt("Spine2",pitch*0.12)
		tilt("Head",pitch*0.18)

func fp_pose(kind: String, ads: float, time: float) -> void:
	if kind=="Relaxed":
		fp_stance()
		arm("Left",Vector3(-0.27,0.99,0.04),0,false)
		arm("Right",Vector3(0.27,0.99,0.04),0,false)
		pose_hand("Left","Relaxed"); pose_hand("Right","Relaxed")
		return
	held(kind,0,time,true)
	if kind not in ["Rifle","Pistol"] or ads<=0: return
	var target: Vector3 = Vector3(0,1.65-(0.100 if kind=="Rifle" else 0.070),-0.52 if kind=="Rifle" else -0.43)+GRIPS[kind]
	var right := global_point("RightHand").lerp(target,ads)
	arm("Right",right,0)
	arm("Left",right+SUPPORTS[kind]-GRIPS[kind],0)
	global_rotation(index("LeftHand"),support_basis(kind))
	pose_hand("Right",kind+"_Right")
	pose_hand("Left","Rifle_LeftSupport" if kind=="Rifle" else "Pistol_Left")

func journal_frame(time: float, fp: bool) -> Transform3D:
	var u := smoothstep(0,1,clampf(time/0.88,0,1))
	var down := Vector3(0.12,0.98,-0.28)
	var up := Vector3(0.102,1.40,-0.40)
	if fp:
		down = Vector3(0.12,0.93,-0.45)
		up = Vector3(0.105,1.59,-0.48)
	return Transform3D(Basis.from_euler(Vector3(lerpf(-0.75,-0.28 if fp else -0.72,u),0,lerpf(-0.18,0,u))).scaled(Vector3.ONE*(1.0 if fp else 0.8)),down.lerp(up,u))

func journal_grip(side: String) -> Transform3D:
	# The open spread extends to X=-0.32..0.11. Hold its lower outside edges.
	var distal := Vector3.UP
	var normal := Vector3.LEFT if side=="Right" else Vector3.RIGHT
	return Transform3D(palm_basis(side,distal,normal),Vector3(-0.335 if side=="Left" else 0.120,-0.188,-0.017))

func journal(time: float, duration: float, closing: bool = false, first_person: bool = false) -> void:
	fp_stance() if first_person else stance()
	var t := 0.88*(1.0-clampf(time/duration,0,1)) if closing else time*0.88/duration
	journal_transform = journal_frame(t,first_person)
	for side in ["Left","Right"]:
		var grip := journal_transform*journal_grip(side)
		arm(side,grip.origin,0)
		global_rotation(index(side+"Hand"),grip.basis)
		pose_hand(side,"Journal_"+side)
	tilt("Head",-0.18*smoothstep(0,0.88,t))

func fp_stance() -> void:
	stance()
	# Dedicated view rig anchors. Full-body proportions/poses remain untouched.
	for side in ["Left","Right"]:
		var bone:=index(side+"Arm"); var parent:=parents[bone]
		var anchor:=FP_LEFT_ANCHOR if side=="Left" else Vector3(0.26,1.46,0.12)
		rig.set_bone_pose_position(bone,rig.get_bone_global_pose(parent).affine_inverse()*anchor)
		rig.force_update_all_bone_transforms()

func vector(values: Array) -> Vector3: return Vector3(values[0],values[1],values[2])

func sample_basis(values: Array) -> Basis: return Basis(vector(values[0]),vector(values[1]),vector(values[2])).orthonormalized()

func reference_action(kind: String, clip: String, time: float, duration: float, first: bool) -> void:
	held(kind,0,0,first)
	var label := "rifle" if kind=="Rifle" else "pistol" if kind=="Pistol" else "knife_pose"
	var idle_clip := "Fire" if kind=="Rifle" else "Armature|Shoot" if kind=="Pistol" else "Armature|Idle"
	var idle := motion(label,idle_clip,0)
	var source_duration := float(reference_motion[label][clip].duration) if reference_motion.has(label) and reference_motion[label].has(clip) else 1.0
	var phase := clampf(time/duration,0,1)
	var data := motion(label,clip,phase*source_duration)
	# End poses blend back into the fitted grip instead of snapping when the
	# gameplay reload duration differs from the reference clip duration.
	var blend := smoothstep(0,0.06,phase)*(1-smoothstep(0.90,1,phase))
	var homes: Dictionary = {}; var bases: Dictionary = {}
	for side in ["Right","Left"]:
		homes[side]=global_point(side+"Hand"); bases[side]=rig.get_bone_global_pose(index(side+"Hand")).basis
	for side in ["Right","Left"]:
		var offset := (vector(data[side].wrist)-vector(idle[side].wrist))*blend
		# Source FPS rigs can use very long camera-space arms. Fit the measured
		# motion excursion to the native upper/lower arm reach.
		offset=offset.limit_length(0.30)
		arm(side,homes[side]+offset,0,side=="Right" or kind!="Knife")
		var delta_basis := sample_basis(data[side].palm)*sample_basis(idle[side].palm).inverse()
		var rotation := Quaternion.IDENTITY.slerp(delta_basis.get_rotation_quaternion(),blend)
		anatomical_wrist(side,Basis(rotation)*bases[side])
		reference_fingers(side,data[side])

func build(first_person: bool = false) -> AnimationLibrary:
	if first_person: return build_fp()
	super.build(false)
	for kind in ["Rifle","Pistol"]:
		library.remove_animation(kind+"Reload")
		var duration := 2.1 if kind=="Rifle" else 1.35
		add_clip(kind+"Reload",duration,false,func(t): reference_action(kind,"Reload" if kind=="Rifle" else "Armature|Reload",t,duration,false))
	library.remove_animation("KnifeAttack")
	add_clip("KnifeAttack",0.42,false,func(t): reference_action("Knife","Armature|Fire1",t,0.42,false))
	# World hands and the independent book must use the same clip clock.
	# These transitions also match the gameplay journal phases sent by the owner.
	for clip in ["JournalOpen","JournalReading","JournalClose"]: library.remove_animation(clip)
	add_clip("JournalOpen",0.88,false,func(t): journal(t,0.88,false,false))
	add_clip("JournalReading",3.0,true,func(t): journal(0.88,0.88,false,false))
	add_clip("JournalClose",0.72,false,func(t): journal(t,0.72,true,false))
	return library

func build_fp() -> AnimationLibrary:
	fp_authoring=true
	var reset:=Animation.new(); reset.length=0.01
	var reset_position:=reset.add_track(Animation.TYPE_POSITION_3D); reset.track_set_path(reset_position,NodePath(".")); reset.position_track_insert_key(reset_position,0,Vector3(0,-1.65,0))
	library.add_animation("RESET",reset)
	var draw:=Animation.new(); draw.length=0.32
	var draw_position:=draw.add_track(Animation.TYPE_POSITION_3D); draw.track_set_path(draw_position,NodePath("."))
	for point in [[0.0,Vector3(0,-1.83,0.06)],[0.10,Vector3(0,-1.77,0.04)],[0.22,Vector3(0,-1.67,0.006)],[0.32,Vector3(0,-1.65,0)]]: draw.position_track_insert_key(draw_position,point[0],point[1])
	library.add_animation("Draw",draw)
	var stow:=Animation.new(); stow.length=0.32
	var stow_position:=stow.add_track(Animation.TYPE_POSITION_3D); stow.track_set_path(stow_position,NodePath("."))
	for point in [[0.0,Vector3(0,-1.65,0)],[0.12,Vector3(0,-1.78,0.02)],[0.32,Vector3(0,-2.10,0.08)]]: stow.position_track_insert_key(stow_position,point[0],point[1])
	library.add_animation("Stow",stow)
	for kind in ["Relaxed","Rifle","Pistol","Flashlight","Knife","Fuse","Fuel","Carry"]:
		add_clip(kind+"Idle",3.0,true,func(t): fp_pose(kind,0,t))
		if kind in ["Rifle","Pistol"]: add_clip(kind+"ADS",3.0,true,func(t): fp_pose(kind,1,t))
	for pose in ["Relaxed","Pistol_Right","Pistol_Left","Rifle_Right","Rifle_LeftSupport","Flashlight","Journal_Left","Journal_Right"]:
		add_clip("HandPose_"+pose,1,true,func(t): fp_pose("Relaxed",0,0); pose_hand("Left" if pose.ends_with("Left") or "LeftSupport" in pose else "Right",pose))
	add_clip("JournalOpen",0.88,false,func(t): journal(t,0.88,false,true))
	add_clip("JournalReading",3.0,true,func(t): journal(0.88,0.88,false,true))
	add_clip("JournalClose",0.72,false,func(t): journal(t,0.72,true,true))
	for kind in ["Rifle","Pistol"]:
		var duration := 2.1 if kind=="Rifle" else 1.35
		add_clip(kind+"Reload",duration,false,func(t): reference_action(kind,"Reload" if kind=="Rifle" else "Armature|Reload",t,duration,true))
		add_clip(kind+"Recoil",0.16,false,func(t): rig.reset_bone_poses(); tilt("RightHand",curve(t/0.16,[[0.0,Vector3.ZERO],[0.12,Vector3(0.045,0,0)],[1.0,Vector3.ZERO]]).x))
	for kind in ["Rifle","Pistol","Flashlight"]:
		add_clip(kind+"Battery",1.10,false,func(t): fp_pose(kind,0,0); arm("Left",curve(t/1.10,[[0.0,global_point("LeftHand")],[0.28,Vector3(0.10,1.30,-0.31)],[0.66,Vector3(0.12,1.34,-0.34)],[1.0,Vector3(-0.25,1.08,-0.20)]]),0); pose_hand("Left","Pistol_Left"))
	add_clip("KnifeAttack",0.42,false,func(t): reference_action("Knife","Armature|Fire1",t,0.42,true))
	return library

func fp_graph() -> AnimationNodeBlendTree:
	var tree := AnimationNodeBlendTree.new()
	var choice := AnimationNodeTransition.new()
	var kinds := ["Relaxed","Rifle","Pistol","Flashlight","Knife","Fuse","Fuel","Carry"]
	choice.set("input_count",kinds.size()); choice.xfade_time=0.18
	for i in kinds.size():
		var kind: String = kinds[i]
		choice.set("input_%d/name"%i,kind)
		if kind in ["Rifle","Pistol"]:
			var aim := AnimationNodeBlendSpace1D.new()
			aim.min_space=0; aim.max_space=1
			aim.add_blend_point(clip_node(kind+"Idle"),0)
			aim.add_blend_point(clip_node(kind+"ADS"),1)
			tree.add_node(kind,aim)
		else: tree.add_node(kind,clip_node(kind+"Idle"))
	tree.add_node("Equipment",choice)
	for i in kinds.size(): tree.connect_node("Equipment",i,kinds[i])
	var actions := ["RifleReload","PistolReload","RifleBattery","PistolBattery","FlashlightBattery","KnifeAttack"]
	var action := AnimationNodeTransition.new(); action.set("input_count",actions.size())
	for i in actions.size():
		action.set("input_%d/name"%i,actions[i]); tree.add_node(actions[i],clip_node(actions[i]))
	tree.add_node("Action",action)
	for i in actions.size(): tree.connect_node("Action",i,actions[i])
	var handling := AnimationNodeOneShot.new(); handling.fadein_time=0.08; handling.fadeout_time=0.16
	tree.add_node("Handling",handling); tree.connect_node("Handling",0,"Equipment"); tree.connect_node("Handling",1,"Action")
	var recoil := AnimationNodeTransition.new(); recoil.set("input_count",2)
	for i in 2:
		var kind: String = ["Rifle","Pistol"][i]
		recoil.set("input_%d/name"%i,kind); tree.add_node(kind+"Recoil",clip_node(kind+"Recoil"))
	tree.add_node("Recoil",recoil); tree.connect_node("Recoil",0,"RifleRecoil"); tree.connect_node("Recoil",1,"PistolRecoil")
	var kick := AnimationNodeOneShot.new(); kick.mix_mode=AnimationNodeOneShot.MIX_MODE_ADD; kick.fadein_time=0.01; kick.fadeout_time=0.04
	upper_filter(kick)
	tree.add_node("Kick",kick); tree.connect_node("Kick",0,"Handling"); tree.connect_node("Kick",1,"Recoil")
	var draw:=AnimationNodeOneShot.new(); draw.mix_mode=AnimationNodeOneShot.MIX_MODE_ADD; draw.fadein_time=0.02; draw.fadeout_time=0.06
	tree.add_node("DrawClip",clip_node("Draw")); tree.add_node("Draw",draw)
	tree.connect_node("Draw",0,"Kick"); tree.connect_node("Draw",1,"DrawClip")
	var stow:=AnimationNodeOneShot.new(); stow.mix_mode=AnimationNodeOneShot.MIX_MODE_ADD; stow.fadein_time=0.0; stow.fadeout_time=0.0
	tree.add_node("StowClip",clip_node("Stow")); tree.add_node("Stow",stow)
	tree.connect_node("Stow",0,"Draw"); tree.connect_node("Stow",1,"StowClip")
	var state := AnimationNodeStateMachine.new()
	# Use a separate state machine for the book, mixed over normal equipment.
	for label in ["JournalOpen","JournalReading","JournalClose"]:
		var book_clip:=AnimationNodeBlendTree.new()
		book_clip.add_node("Clip",clip_node(label)); book_clip.add_node("Time",AnimationNodeTimeSeek.new())
		book_clip.connect_node("Time",0,"Clip"); book_clip.connect_node("output",0,"Time")
		state.add_node(label,book_clip)
	for pair in [["JournalOpen","JournalReading"],["JournalClose","JournalReading"]]:
		var transition := AnimationNodeStateMachineTransition.new(); transition.xfade_time=0.12
		if pair[0]=="JournalOpen": transition.advance_mode=AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO; transition.switch_mode=AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
		state.add_transition(pair[0],pair[1],transition)
	for pair in [["JournalReading","JournalClose"],["JournalOpen","JournalClose"],["JournalClose","JournalOpen"]]:
		var transition := AnimationNodeStateMachineTransition.new(); transition.xfade_time=0.10; state.add_transition(pair[0],pair[1],transition)
	tree.add_node("Journal",state)
	var blend := AnimationNodeBlend2.new()
	tree.add_node("BookBlend",blend); tree.connect_node("BookBlend",0,"Stow"); tree.connect_node("BookBlend",1,"Journal"); tree.connect_node("output",0,"BookBlend")
	return tree


