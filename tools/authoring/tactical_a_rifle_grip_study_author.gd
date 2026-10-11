extends "res://tools/authoring/rifle_grip_study_author.gd"
## Tactical A contact correction only; shared approved rifle pose stays intact.
func rifle_pose(style:int,first_person:bool=false)->void:
 super.rifle_pose(style,first_person)
 var targets:Array=[]
 for segment in [2,3,4]:
  targets.append(global_point("LeftHandThumb"+str(segment))+Vector3([.006,.012,.018][segment-2],[-.004,-.008,-.012][segment-2],0))
 aim_finger("Left","Thumb",targets)
