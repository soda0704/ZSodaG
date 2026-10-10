extends "res://tools/authoring/presentation_animation_author.gd"
## Isolated pistol pose study. Generates preview animation assets only.
const RIGHT_GRIP := Vector3(.045,-.060,.060)
func shooting_basis()->Basis:return hand_basis("Right",0,true)
func support_grip(style:int)->Vector3:return Vector3(-.060,-.075,.072) if style==0 else Vector3(-.060,-.087,.057)
func stance(_crouch:float=0.0)->void:
	pass
func fit_finger(side:String,finger:String,angles:Array,spread:float=0.0)->void:
	var wrist:=index(side+"Hand")
	var frame:=rig.get_bone_global_pose(wrist).basis*rests[wrist].basis.inverse()*anatomical_frame(side)
	var bend:=0.0
	for segment in [1,2,3]:
		bend+=deg_to_rad(angles[segment-1])
		var b:=index(side+"Hand"+finger+str(segment));var end:=index(side+"Hand"+finger+str(segment+1))
		var desired:=frame*Vector3(sin(deg_to_rad(spread)),cos(bend)*cos(deg_to_rad(spread)),sin(bend)*cos(deg_to_rad(spread)))
		var current:Vector3=(global_point(names[end])-global_point(names[b])).normalized()
		global_rotation(b,Basis(Quaternion(current,desired))*rig.get_bone_global_pose(b).basis)
func aim_finger(side:String,finger:String,targets:Array)->void:
	for segment in [1,2,3]:
		var b:=index(side+"Hand"+finger+str(segment));var end:=index(side+"Hand"+finger+str(segment+1))
		var current:Vector3=(global_point(names[end])-global_point(names[b])).normalized()
		var direction:Vector3=(targets[segment-1]-global_point(names[b])).normalized()
		global_rotation(b,Basis(Quaternion(current,direction))*rig.get_bone_global_pose(b).basis)
var support_pole:=Vector3.ZERO
func two_bone(root_name:String,middle_name:String,end_name:String,target:Vector3,pole:Vector3)->void:
	super.two_bone(root_name,middle_name,end_name,target,support_pole if root_name=="LeftArm" and not support_pole.is_zero_approx() else pole)
func raise_trigger_knuckle()->void:
	# Preserve the complete distal phalanx, including the actual fingertip.
	var dip:=global_point("RightHandIndex3")
	var tip:=global_point("RightHandIndex4")
	var pip:=global_point("RightHandIndex2")
	var distal_basis:=rig.get_bone_global_pose(index("RightHandIndex3")).basis
	two_bone("RightHandIndex1","RightHandIndex2","RightHandIndex3",dip,pip+Vector3.UP*.005)
	global_rotation(index("RightHandIndex3"),distal_basis)
	var drift:=global_point("RightHandIndex4").distance_to(tip)
	print("TRIGGER tip drift mm ",drift*1000," knuckle lift mm ",(global_point("RightHandIndex2").y-pip.y)*1000)
	assert(drift<.0002)
func fit_support(target:Vector3)->void:
	var desired:=palm_basis("Left",Vector3(0,.38,-.925),Vector3.RIGHT)
	var shoulder:=global_point("LeftArm")
	var axis:Vector3=(target-shoulder).normalized()
	var u:Vector3=(Vector3.DOWN-axis*axis.dot(Vector3.DOWN)).normalized()
	var v:=axis.cross(u).normalized()
	var best:=Vector3.ZERO;var score:=INF
	var candidates:Array[Vector3]=[Vector3(-.42,1.03,.08)]
	for sample in 24:candidates.append(shoulder+(u*cos(sample*TAU/24)+v*sin(sample*TAU/24))*.7)
	for pole in candidates:
		support_pole=pole;arm("Left",target,0);global_rotation(index("LeftHand"),desired)
		var actual:Basis=rig.get_bone_global_pose(index("LeftHand")).basis
		var elbow:=global_point("LeftForeArm")
		var error:=rad_to_deg((actual*desired.inverse()).get_rotation_quaternion().get_angle())
		var cost:=error*10+maxf(0,elbow.y-target.y+.10)*100+elbow.distance_to(Vector3(-.32,target.y-.22,.02))*2
		if cost<score:score=cost;best=pole
	support_pole=best;arm("Left",target,0);global_rotation(index("LeftHand"),desired)
func pistol_pose(style:int,first_person:bool=false)->void:
	if first_person:fp_stance()
	var gun:=Vector3(.095,1.535,-.52) if first_person else Vector3(.095,1.455,-.36)
	var wrist:=gun+RIGHT_GRIP
	arm("Right",wrist,0)
	pose_hand("Right","Pistol_Right")
	for finger in ["Middle","Ring","Pinky"]:fit_finger("Right",finger,[78.,74.,38.])
	aim_finger("Right","Index",[gun+Vector3(.031,.001,-.045),gun+Vector3(.018,.010,-.070),gun+Vector3(.003,.009,-.069)])
	raise_trigger_knuckle()
	aim_finger("Right","Thumb",[gun+Vector3(-.005,.009,.050),gun+Vector3(-.027,.005,.015),gun+Vector3(-.027,.003,-.015)])
	var left_grip:=support_grip(style)
	fit_support(gun+left_grip)
	for finger in ["Index","Middle","Ring","Pinky"]:fit_finger("Left",finger,[35.,50.,25.])
	aim_finger("Left","Thumb",[gun+Vector3(-.036,-.008,-.019),gun+Vector3(-.034,.004,-.050),gun+Vector3(-.032,.005,-.072)])
