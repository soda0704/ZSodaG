extends "res://tools/authoring/knife_grip_study_author.gd"
## Native cylindrical grip study, separate from accepted knife assets.
const FUEL_SCALE:=1.0
const FUEL_RIGHT_GRIP:=Vector3(.028,.028,-.072)
func fuel_item_basis()->Basis:return Basis(Vector3.RIGHT,deg_to_rad(45.))*Basis(Vector3.RIGHT,deg_to_rad(90.))
func fuel_hand_basis()->Basis:return knife_hand_basis()
func fuel_pose(first_person:bool)->void:
 knife_pose(first_person)
 var curls:={"Index":[76.,70.,25.],"Middle":[76.,68.,23.],"Ring":[72.,62.,20.],"Pinky":[72.,61.,20.]}
 for finger in curls:fit_finger("Right",finger,curls[finger])





