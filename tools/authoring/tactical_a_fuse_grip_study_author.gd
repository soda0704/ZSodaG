extends "res://tools/authoring/fuse_grip_study_author.gd"
func fuel_pose(first_person:bool)->void:
 super.fuel_pose(first_person)
 fit_finger("Right","Index",[71.,65.,23.])
 var knuckle:=global_point("RightHandIndex2")
 aim_finger("Right","Thumb",[knuckle+Vector3(-.005,.024,.019),knuckle+Vector3(-.013,.012,.003),knuckle+Vector3(-.003,.003,-.014)])
