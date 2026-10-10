extends "res://tools/authoring/knife_grip_study_author.gd"
## A cylindrical hold derived from the accepted knife hand, with independent aim.
const FLASHLIGHT_RIGHT_GRIP:=Vector3(.038,.038,.028)
func flashlight_item_basis()->Basis:return Basis(Vector3.RIGHT,deg_to_rad(-8.))
func flashlight_hand_basis()->Basis:
	return Basis(Vector3.RIGHT,deg_to_rad(-8.))*knife_hand_basis()
func flashlight_pose(first_person:bool)->void:
	knife_pose(first_person)
	var wrist:=global_point("RightHand")
	fit_flashlight_arm("Right",wrist,flashlight_hand_basis())
	var item:=Transform3D(flashlight_item_basis(),wrist-flashlight_item_basis()*FLASHLIGHT_RIGHT_GRIP)
	for finger in ["Index","Middle","Ring","Pinky"]:
		var proximal:Vector3=item.affine_inverse()*global_point("RightHand"+finger+"1")
		var z:float={"Index":-.055,"Middle":-.027,"Ring":.001,"Pinky":.027}[finger]
		two_bone("RightHand"+finger+"1","RightHand"+finger+"2","RightHand"+finger+"3",item*Vector3(-.021,-.005,z),item*Vector3(.004,-.047,z))
		var distal:=index("RightHand"+finger+"3");var tip:=index("RightHand"+finger+"4")
		var current:Vector3=(global_point(names[tip])-global_point(names[distal])).normalized()
		var toward:Vector3=(item*Vector3(-.011,.017,z)-global_point(names[distal])).normalized()
		global_rotation(distal,Basis(Quaternion(current,toward))*rig.get_bone_global_pose(distal).basis)
	var contact:Vector3=item.affine_inverse()*global_point("RightHandIndex2")
	aim_finger("Right","Thumb",[item*Vector3(.015,.022,contact.z-.012),item*Vector3(-.016,.017,contact.z-.009),item*Vector3(-.023,.0,contact.z-.004)])
	if not first_person:seat_elbow_shells()

func fit_flashlight_arm(side:String,target:Vector3,desired:Basis)->void:
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
		var cost:=error+maxf(0,elbow.y-target.y+.08)*2000+elbow.distance_to(preferred)*200
		if cost<score:score=cost;best=pole
	if side=="Left":support_pole=best
	else:right_pole=best
	arm(side,target,0);global_rotation(index(side+"Hand"),desired)
