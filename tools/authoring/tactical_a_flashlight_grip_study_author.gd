extends "res://tools/authoring/flashlight_grip_study_author.gd"
var contact_reference:Skeleton3D
func flashlight_hand_basis()->Basis:
 if contact_reference==null:return super.flashlight_hand_basis()
 var reference_author=load("res://tools/authoring/pistol_grip_study_author.gd").new()
 reference_author.initialize(contact_reference,{"meshes":[]},{})
 var hand:=contact_reference.find_bone("RightHand")
 var reference_frame:Basis=contact_reference.get_bone_global_pose(hand).basis*contact_reference.get_bone_global_rest(hand).basis.inverse()*reference_author.anatomical_frame("Right")
 return Basis(Vector3.RIGHT,deg_to_rad(-17.))*palm_basis("Right",reference_frame.y,reference_frame.z)
func fit_flashlight_arm(side:String,target:Vector3,desired:Basis)->void:
 if contact_reference!=null:target=contact_reference.get_bone_global_pose(contact_reference.find_bone(side+"Hand")).origin
 fit_rifle_arm(side,target,desired)
func flashlight_pose(first_person:bool)->void:
 super.flashlight_pose(first_person)
 var curls:={"Index":[83.,67.,24.],"Middle":[84.,67.,24.],"Ring":[87.,71.,26.],"Pinky":[92.,82.,35.]}
 for finger in curls:fit_finger("Right",finger,curls[finger])
 var item:=Transform3D(flashlight_item_basis(),global_point("RightHand")-flashlight_item_basis()*FLASHLIGHT_RIGHT_GRIP)
 var knuckle:Vector3=item.affine_inverse()*global_point("RightHandIndex2")
 aim_finger("Right","Thumb",[item*Vector3(.012,.025,knuckle.z-.012),item*Vector3(-.018,.016,knuckle.z-.009),item*Vector3(-.025,-.006,knuckle.z-.004)])
 fit_finger("Right","Index",[79.,62.,22.])
 # Extended thumb follows the barrel toward the lens, without a curled tip.
 var thumb_direction:Vector3=flashlight_item_basis()*Vector3(0,0,-1)
 for segment in [1,2,3]:
  var bone:=index("RightHandThumb"+str(segment))
  var direction:Vector3=(global_point("RightHandThumb"+str(segment+1))-global_point("RightHandThumb"+str(segment))).normalized()
  global_rotation(bone,Basis(Quaternion(direction,direction.lerp(thumb_direction,.20).normalized()))*rig.get_bone_global_pose(bone).basis)
 var target:Vector3=contact_reference.get_bone_global_pose(contact_reference.find_bone("RightHand")).origin
 print("REFERENCE wrist position drift mm ",global_point("RightHand").distance_to(target)*1000)
 # Raise contact arcs toward the barrel without stretching native phalanges.
 for finger in ["Index","Middle","Ring","Pinky"]:
  var dip:=global_point("RightHand"+finger+"3")
  var pip:=global_point("RightHand"+finger+"2")
  var distal:=index("RightHand"+finger+"3")
  var distal_basis:Basis=rig.get_bone_global_pose(distal).basis
  two_bone("RightHand"+finger+"1","RightHand"+finger+"2","RightHand"+finger+"3",dip+Vector3.UP*({"Index":.018,"Middle":.023,"Ring":.030,"Pinky":.035}[finger]),pip+Vector3.UP*({"Index":.016,"Middle":.021,"Ring":.028,"Pinky":.033}[finger]))
  global_rotation(distal,distal_basis)
  if finger=="Pinky":
   var origin:=global_point("RightHandPinky3")
   var tip:=global_point("RightHandPinky4")
   global_rotation(distal,Basis(Quaternion((tip-origin).normalized(),(tip+Vector3(0,-.004,-.002)-origin).normalized()))*rig.get_bone_global_pose(distal).basis)
 # Fit the complete contact arc to the approved hand, starting from the
 # previously adjusted pose, retaining native segment lengths.
 for finger in ["Index","Middle","Ring","Pinky"]:
  var reference_pip:Vector3=contact_reference.get_bone_global_pose(contact_reference.find_bone("RightHand"+finger+"2")).origin
  var reference_dip:Vector3=contact_reference.get_bone_global_pose(contact_reference.find_bone("RightHand"+finger+"3")).origin
  var reference_tip:Vector3=contact_reference.get_bone_global_pose(contact_reference.find_bone("RightHand"+finger+"4")).origin
  two_bone("RightHand"+finger+"1","RightHand"+finger+"2","RightHand"+finger+"3",reference_dip,reference_pip)
  var distal:=index("RightHand"+finger+"3")
  var current:Vector3=(global_point("RightHand"+finger+"4")-global_point("RightHand"+finger+"3")).normalized()
  global_rotation(distal,Basis(Quaternion(current,(reference_tip-reference_dip).normalized()))*rig.get_bone_global_pose(distal).basis)










