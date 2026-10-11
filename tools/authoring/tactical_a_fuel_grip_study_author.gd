extends "res://tools/authoring/fuel_grip_study_author.gd"
func fuel_pose(first_person:bool)->void:
 super.fuel_pose(first_person)
 var curls:={"Index":[78.,70.,24.],"Middle":[80.,72.,24.],"Ring":[80.,67.,18.],"Pinky":[90.,77.,20.]}
 for finger in curls:fit_finger("Right",finger,curls[finger])
