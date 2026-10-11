extends "res://tools/authoring/pistol_grip_study_author.gd"
## Photo study: thumbs on pages, remaining fingers support the back cover.
func correct_contacts(book:Node3D)->void:
	var inverse:=book.transform.affine_inverse()
	for side in ["Right","Left"]:
		var sign_x:=1.0 if side=="Left" else -1.0
		var thumb_root:Vector3=inverse*global_point(side+"HandThumb1")
		var thumb_targets:Array=[]
		for segment in 3:
			thumb_targets.append(book.transform*(thumb_root+Vector3(sign_x*[.006,.012,.016][segment],[.045,.080,.105][segment],.020-thumb_root.z)))
		aim_finger(side,"Thumb",thumb_targets)
		for finger in ["Index","Middle","Ring","Pinky"]:
			var targets:Array=[]
			var finger_root:Vector3=inverse*global_point(side+"Hand"+finger+"1")
			for segment in [2,3,4]:
				var contact:Vector3=inverse*global_point(side+"Hand"+finger+str(segment))
				if finger=="Index":
					contact.x=finger_root.x+sign_x*[.002,.024,.044][segment-2]
					contact.y=finger_root.y+[.032,.051,.056][segment-2]
					contact.z=[-.026,-.040,-.041][segment-2]
				elif finger=="Middle":contact.z=-.044
				targets.append(book.transform*contact)
			aim_finger(side,finger,targets)
		# A small outward wrist adjustment, with the approved thumb contact retained.
		var thumb_dip:=global_point(side+"HandThumb3")
		var thumb_pip:=global_point(side+"HandThumb2")
		var thumb_tip:=global_point(side+"HandThumb4")
		var thumb_basis:Basis=rig.get_bone_global_pose(index(side+"HandThumb3")).basis
		var wrist:=index(side+"Hand")
		global_rotation(wrist,Basis(book.transform.basis.z.normalized(),sign_x*deg_to_rad(9))*rig.get_bone_global_pose(wrist).basis)
		var contact_roots:Dictionary={}
		for finger in ["Index","Middle","Ring","Pinky"]:
			contact_roots[finger]=inverse*global_point(side+"Hand"+finger+"1")
		# Bring the palm plane toward the cover rather than moving the book.
		global_rotation(wrist,Basis(book.transform.basis.y.normalized(),sign_x*deg_to_rad(20))*rig.get_bone_global_pose(wrist).basis)
		two_bone(side+"HandThumb1",side+"HandThumb2",side+"HandThumb3",thumb_dip,thumb_pip)
		global_rotation(index(side+"HandThumb3"),thumb_basis)
		print(side," thumb contact drift mm ",global_point(side+"HandThumb4").distance_to(thumb_tip)*1000)
		for finger in ["Index","Middle","Ring","Pinky"]:
			var finger_root:Vector3=contact_roots[finger]
			var row:int=["Index","Middle","Ring","Pinky"].find(finger)
			var targets:Array=[]
			for segment in 3:
				var contact:=finger_root+Vector3(sign_x*[.040,.070,.091][segment],[.028,.036,.034][segment]-row*.014,0)
				contact.z=[-.032,-.039,-.040][segment]-row*.003
				targets.append(book.transform*contact)
			aim_finger(side,finger,targets)

		# Move the complete hand with arm IK; do not translate or scale phalanges.
		var hand_basis:Basis=rig.get_bone_global_pose(wrist).basis
		thumb_dip=global_point(side+"HandThumb3")
		thumb_pip=global_point(side+"HandThumb2")
		thumb_basis=rig.get_bone_global_pose(index(side+"HandThumb3")).basis
		var inward:Vector3=book.transform.basis.orthonormalized()*Vector3(sign_x*.014,0,0)
		var target:=global_point(side+"Hand")+inward
		var elbow:=global_point(side+"ForeArm")
		two_bone(side+"Arm",side+"ForeArm",side+"Hand",target,elbow)
		global_rotation(wrist,hand_basis)
		two_bone(side+"HandThumb1",side+"HandThumb2",side+"HandThumb3",thumb_dip,thumb_pip)
		global_rotation(index(side+"HandThumb3"),thumb_basis)
		print(side," complete hand inward shift mm ",inward.length()*1000)
		# Small separate release away from the cover, using rotations only.
		var release_normal:Vector3=-book.transform.basis.z.normalized()
		for finger in ["Index","Middle","Ring"]:
			var strength:float={"Index":1.0,"Middle":.65,"Ring":.20}[finger]
			for segment in [1,2,3]:
				var bone:=index(side+"Hand"+finger+str(segment))
				var direction:Vector3=(global_point(side+"Hand"+finger+str(segment+1))-global_point(side+"Hand"+finger+str(segment))).normalized()
				var relaxed:Vector3=(direction+release_normal*[.045,.070,.045][segment-1]*strength).normalized()
				global_rotation(bone,Basis(Quaternion(direction,relaxed))*rig.get_bone_global_pose(bone).basis)
		if side=="Right":
			var contacts:Dictionary={}
			for finger in ["Thumb","Index","Middle","Ring","Pinky"]:
				contacts[finger]=[global_point(side+"Hand"+finger+"2"),global_point(side+"Hand"+finger+"3"),global_point(side+"Hand"+finger+"4"),rig.get_bone_global_pose(index(side+"Hand"+finger+"3")).basis]
			var pivot:=Vector3.ZERO
			for finger in contacts:pivot+=contacts[finger][2]
			pivot/=contacts.size()
			var turn:=Basis(Vector3.RIGHT,deg_to_rad(-9))
			var desired_hand:Basis=turn*rig.get_bone_global_pose(wrist).basis
			var new_wrist:Vector3=pivot+turn*(global_point(side+"Hand")-pivot)
			two_bone(side+"Arm",side+"ForeArm",side+"Hand",new_wrist,global_point(side+"ForeArm"))
			global_rotation(wrist,desired_hand)
			for finger in contacts:
				var contact:Array=contacts[finger]
				two_bone(side+"Hand"+finger+"1",side+"Hand"+finger+"2",side+"Hand"+finger+"3",contact[1],contact[0])
				global_rotation(index(side+"Hand"+finger+"3"),contact[3])
				for iteration in 80:
					if global_point(side+"Hand"+finger+"4").distance_to(contact[2])<.00001:break
					for segment in [3,2,1]:
						var bone:=index(side+"Hand"+finger+str(segment))
						var origin:Vector3=rig.get_bone_global_pose(bone).origin
						var current:Vector3=(global_point(side+"Hand"+finger+"4")-origin).normalized()
						var desired:Vector3=(contact[2]-origin).normalized()
						global_rotation(bone,Basis(Quaternion(current,desired))*rig.get_bone_global_pose(bone).basis)
				var drift:float=global_point(side+"Hand"+finger+"4").distance_to(contact[2])
				print("Fixed ",finger," tip drift mm ",drift*1000)
				assert(drift<.0005)


