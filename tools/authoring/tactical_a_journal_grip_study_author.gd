extends "res://tools/authoring/rifle_grip_study_author.gd"
var contact_reference:Skeleton3D
func correct_contacts(book:Node3D)->void:
 var reference_author=load("res://tools/authoring/pistol_grip_study_author.gd").new()
 reference_author.initialize(contact_reference,{"meshes":[]},{})
 for side in ["Right","Left"]:
  var hand:=contact_reference.find_bone(side+"Hand")
  var frame:Basis=contact_reference.get_bone_global_pose(hand).basis*contact_reference.get_bone_global_rest(hand).basis.inverse()*reference_author.anatomical_frame(side)
  var sign_x:=1.0 if side=="Left" else -1.0
  var turn:=Basis(book.transform.basis.y.normalized(),sign_x*deg_to_rad(8.))
  fit_rifle_arm(side,contact_reference.get_bone_global_pose(hand).origin,turn*palm_basis(side,frame.y,frame.z))
  for finger in ["Thumb","Index","Middle","Ring","Pinky"]:
   var prefix:String=side+"Hand"+finger
   var ref_root:=contact_reference.get_bone_global_pose(contact_reference.find_bone(prefix+"1")).origin
   var ref_tip:=contact_reference.get_bone_global_pose(contact_reference.find_bone(prefix+"4")).origin
   var straight:Vector3=(ref_tip-ref_root).normalized()
   for segment in [1,2,3]:
    var bone:=index(prefix+str(segment))
    var ref_origin:=contact_reference.get_bone_global_pose(contact_reference.find_bone(prefix+str(segment))).origin
    var ref_end:=contact_reference.get_bone_global_pose(contact_reference.find_bone(prefix+str(segment+1))).origin
    var direction:Vector3=(global_point(prefix+str(segment+1))-global_point(prefix+str(segment))).normalized()
    var relaxed:Vector3=(ref_end-ref_origin).normalized().slerp(straight,.30 if finger=="Thumb" else .45).normalized()
    global_rotation(bone,Basis(Quaternion(direction,relaxed))*rig.get_bone_global_pose(bone).basis)

