extends "res://tools/authoring/pistol_grip_study_author.gd"
## Native rifle grip previews; the accepted pistol assets are not regenerated.
const RIFLE_RIGHT_GRIP:=Vector3(.040,-.065,.110)
var right_pole:=Vector3.ZERO
func support_grip(style:int)->Vector3:
	var grip:=Vector3(-.072,-.025,-.170 if style==0 else -.195)
	if style==0:grip=Basis(Vector3.FORWARD,deg_to_rad(8.))*grip;grip.z+=.008
	return grip
func rifle_support_basis(style:int=0)->Basis:
	var original:=palm_basis("Left",Vector3(.84,.40,-.36),Vector3.UP)
	return Basis(Vector3.FORWARD,deg_to_rad(8.))*original if style==0 else original
func two_bone(root_name:String,middle_name:String,end_name:String,target:Vector3,pole:Vector3)->void:
	super.two_bone(root_name,middle_name,end_name,target,right_pole if root_name=="RightArm" and not right_pole.is_zero_approx() else pole)
func fit_rifle_arm(side:String,target:Vector3,desired:Basis)->void:
	var shoulder:=global_point(side+"Arm")
	var axis:Vector3=(target-shoulder).normalized()
	var u:Vector3=(Vector3.DOWN-axis*axis.dot(Vector3.DOWN)).normalized()
	var v:=axis.cross(u).normalized()
	var best:=Vector3.ZERO;var score:=INF
	var preferred:=Vector3(-.32 if side=="Left" else .32,target.y-.22,.04)
	var candidates:Array[Vector3]=[Vector3(-.42 if side=="Left" else .42,1.03,.08)]
	for sample in 36:candidates.append(shoulder+(u*cos(sample*TAU/36)+v*sin(sample*TAU/36))*.7)
	for pole in candidates:
		if side=="Left":support_pole=pole
		else:right_pole=pole
		arm(side,target,0);global_rotation(index(side+"Hand"),desired)
		var actual:Basis=rig.get_bone_global_pose(index(side+"Hand")).basis
		var elbow:=global_point(side+"ForeArm")
		var error:=rad_to_deg((actual*desired.inverse()).get_rotation_quaternion().get_angle())
		var cost:=error*10+maxf(0,elbow.y-target.y+.08)*100+elbow.distance_to(preferred)*2
		if cost<score:score=cost;best=pole
	if side=="Left":support_pole=best
	else:right_pole=best
	arm(side,target,0);global_rotation(index(side+"Hand"),desired)
func rifle_pose(style:int,first_person:bool=false)->void:
	if first_person:fp_stance()
	else:
		var head_basis:Basis=rig.get_bone_global_pose(index("Head")).basis
		tilt("Spine2",0,0,-.30);global_rotation(index("Head"),head_basis)
	var gun:=Vector3(.13,1.48,-.46) if first_person else Vector3(.13,1.43,-.28)
	if not first_person:
		# Stock heel seats at the front of the native right shoulder.
		var shoulder_contact:=global_point("RightArm")+Vector3(.015,-.025,-.065)
		gun=shoulder_contact-Vector3(0,0,.272119)
	fit_rifle_arm("Right",gun+RIFLE_RIGHT_GRIP,shooting_basis())
	pose_hand("Right","Rifle_Right")
	for finger in ["Middle","Ring","Pinky"]:fit_finger("Right",finger,[78.,74.,38.])
	aim_finger("Right","Index",[gun+Vector3(.026,.005,-.018),gun+Vector3(.012,-.007,-.037),gun+Vector3(-.007,-.010,-.030)])
	aim_finger("Right","Thumb",[gun+Vector3(-.004,.005,.091),gun+Vector3(-.030,.010,.064),gun+Vector3(-.033,.010,.036)])
	var left_grip:=support_grip(style)
	fit_rifle_arm("Left",gun+left_grip,rifle_support_basis(style))
	for finger in ["Index","Middle","Ring","Pinky"]:fit_finger("Left",finger,[60.,61.,25.] if style==0 else [65.,70.,30.])
	if style==0:
		# Relaxed extended thumb follows the foreguard toward the muzzle.
		var direction:=Vector3(-.06,.20,-.978).normalized()
		for segment in [1,2,3]:
			var bone:=index("LeftHandThumb"+str(segment))
			var end:=index("LeftHandThumb"+str(segment+1))
			var current:Vector3=(global_point(names[end])-global_point(names[bone])).normalized()
			global_rotation(bone,Basis(Quaternion(current,direction))*rig.get_bone_global_pose(bone).basis)
	else:
		aim_finger("Left","Thumb",[gun+Vector3(-.035,.021,left_grip.z-.010),gun+Vector3(-.032,.047,left_grip.z-.035),gun+Vector3(-.028,.050,left_grip.z-.062)])

	if not first_person:seat_elbow_shells()
func seat_elbow_shells()->void:
	for side in ["Left","Right"]:
		var upper:=index(side+"Arm");var forearm:=index(side+"ForeArm");var pad:=index(side+"_Elbow_Pads")
		if pad<0:continue
		# Elbow shell follows flexion, independently of distal forearm pronation.
		var neutral:Basis=rig.get_bone_global_pose(upper).basis*rests[upper].basis.inverse()*rests[forearm].basis
		var rest_axis:Vector3=(rests[index(side+"Hand")].origin-rests[forearm].origin).normalized()
		var baseline:Vector3=neutral*rests[forearm].basis.inverse()*rest_axis
		var actual:Vector3=(global_point(side+"Hand")-global_point(side+"ForeArm")).normalized()
		var hinge:=Basis(Quaternion(baseline.normalized(),actual))*neutral
		var target:=Transform3D(hinge,global_point(side+"ForeArm"))*rig.get_bone_rest(pad)
		global_rotation(pad,target.basis)
		rig.set_bone_pose_position(pad,rig.get_bone_global_pose(forearm).affine_inverse()*target.origin)
		rig.force_update_all_bone_transforms()

		var local_center:=elbow_shell_center(pad)
		var elbow:=global_point(side+"ForeArm")
		var upper_direction:Vector3=(elbow-global_point(side+"Arm")).normalized()
		var outer:Vector3=(upper_direction-actual).normalized()
		if side=="Left":
			global_rotation(pad,Basis(Vector3.FORWARD,deg_to_rad(8.))*rig.get_bone_global_pose(pad).basis)
		var rest_normal:Vector3=((rests[pad]*local_center)-rests[forearm].origin).normalized()
		var local_normal:Vector3=rests[pad].basis.inverse()*rest_normal
		var posed_normal:Vector3=rig.get_bone_global_pose(pad).basis*local_normal
		global_rotation(pad,Basis(Quaternion(posed_normal.normalized(),outer))*rig.get_bone_global_pose(pad).basis)
		var wanted_center:=elbow+outer*.035
		var current_center:Vector3=rig.get_bone_global_pose(pad)*local_center
		var origin:Vector3=rig.get_bone_global_pose(pad).origin+wanted_center-current_center
		rig.set_bone_pose_position(pad,rig.get_bone_global_pose(forearm).affine_inverse()*origin)
		rig.force_update_all_bone_transforms()
		print(side," elbow shell center ",rig.get_bone_global_pose(pad)*local_center," elbow ",elbow)
func elbow_shell_center(pad:int)->Vector3:
	var mesh:Mesh=rig.get_node("Body").mesh
	var points:Array[Vector3]=[]
	for surface in mesh.get_surface_count():
		var arrays:=mesh.surface_get_arrays(surface)
		var ids:PackedInt32Array=arrays[Mesh.ARRAY_BONES];var weights:PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS]
		var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		for vertex in vertices.size():
			var weight:=0.0
			for slot in 4:
				if ids[vertex*4+slot]==pad:weight+=weights[vertex*4+slot]
			if weight>.8:points.append(rests[pad].affine_inverse()*vertices[vertex])
	assert(not points.is_empty())
	var bounds:=AABB(points[0],Vector3.ZERO)
	for point in points:bounds=bounds.expand(point)
	return bounds.get_center()
