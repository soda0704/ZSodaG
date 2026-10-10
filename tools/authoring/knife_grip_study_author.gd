extends "res://tools/authoring/rifle_grip_study_author.gd"
## Isolated knife authoring; no accepted firearm poses are regenerated.
const KNIFE_RIGHT_GRIP:=Vector3(.028,.078,.028)
func knife_item_basis()->Basis:return Basis(Vector3.RIGHT,deg_to_rad(45.))
func knife_hand_basis()->Basis:
	return palm_basis("Right",Vector3(0,-.50,-.866),Vector3.LEFT)
func knife_pose(first_person:bool)->void:
	if first_person:fp_stance()
	var wrist:=Vector3(.22,1.43,-.43) if first_person else Vector3(.24,1.25,-.34)
	fit_rifle_arm("Right",wrist,knife_hand_basis())
	var curls:={"Index":[79.,78.,32.],"Middle":[86.,82.,32.],"Ring":[91.,85.,30.],"Pinky":[96.,87.,28.]}
	for finger in curls:fit_finger("Right",finger,curls[finger])
	var item_basis:=knife_item_basis()
	var knife:=wrist-item_basis*KNIFE_RIGHT_GRIP
	var index_knuckle:=global_point("RightHandIndex2")
	# Thumb travels around the left side before returning onto the index.
	aim_finger("Right","Thumb",[index_knuckle+Vector3(-.005,.026,.023),index_knuckle+Vector3(-.013,.016,.008),index_knuckle+Vector3(-.003,.006,-.010)])
	# Settle index against the handle after thumb placement; keep thumb unchanged.
	fit_finger("Right","Index",[84.,80.,32.])
	# The free hand uses its own relaxed pose, not a second weapon grip.
	arm("Left",Vector3(-.27,1.05,-.24) if first_person else Vector3(-.27,.94,-.06),0,false)
	pose_hand("Left","Relaxed")
	if not first_person:seat_elbow_shells()
