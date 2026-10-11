extends "res://tools/authoring/knife_grip_study_author.gd"
func knife_pose(first_person:bool)->void:
 super.knife_pose(first_person)
 fit_finger("Right","Ring",[88.,78.,27.])
 fit_finger("Right","Pinky",[87.,75.,25.])
 var contacts:Array=[]
 for segment in [2,3,4]:
  contacts.append(global_point("RightHandThumb"+str(segment))+Vector3([.002,.004,.006][segment-2],[-.002,-.004,-.006][segment-2],0))
 aim_finger("Right","Thumb",contacts)

