extends "res://tools/authoring/knife_grip_study_author.gd"
## Side carry: the existing can handle is rotated to the natural finger row.
const FUEL_SCALE:=.72
const FUEL_RIGHT_GRIP:=Vector3(-.020,.355,.05)
func fuel_item_basis()->Basis:return Basis(Vector3.UP,PI*.5)
func fuel_hand_basis()->Basis:return palm_basis("Right",Vector3.DOWN,Vector3.LEFT)
func fuel_pose(first_person:bool)->void:
	knife_pose(first_person)
	var wrist:=Vector3(.30,1.37,-.57) if first_person else Vector3(.40,1.02,-.12)
	fit_rifle_arm("Right",wrist,fuel_hand_basis())
	# Relax the same native curved grip, retaining the opposing thumb.
	var curls:={"Index":[80.,72.,25.],"Middle":[82.,74.,25.],"Ring":[82.,69.,19.],"Pinky":[92.,79.,21.]}
	for finger in curls:fit_finger("Right",finger,curls[finger])
	if not first_person:seat_elbow_shells()
