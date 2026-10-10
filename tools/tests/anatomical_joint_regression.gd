extends SceneTree
## Check actual saved local joint rotations, including the forearm, not just
## coincident IK markers. The previous grip tests missed a 160-degree twist.
var failures:=0
var checks:=0
func _initialize(): run.call_deferred()
func check(ok: bool, label: String):
	checks+=1
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func twist(q: Quaternion, axis: Vector3) -> float:
	if q.w<0:q=-q
	return absf(rad_to_deg(2*atan2(Vector3(q.x,q.y,q.z).dot(axis),q.w)))
func run():
	var clips:Array[String]=["Idle","JournalOpen","JournalReading","JournalClose","RifleReload","PistolReload","KnifeAttack"]
	for kind in ["Rifle","Pistol","Knife","Flashlight","Fuel","Fuse"]:
		for aim in [-1,0,1]:clips.append(kind+"Aim"+str(aim))
	for variant in ["a","b"]:
		for mode in ["body","first_person"]:
			var model:Node3D=load("res://scenes/characters/visuals/tactical_"+variant+"/"+mode+".tscn").instantiate();root.add_child(model)
			var sk:Skeleton3D=model.get_node("Skeleton3D");var ap:AnimationPlayer=model.get_node("AnimationPlayer")
			var list=clips.duplicate() if mode=="body" else ["RelaxedIdle","RifleIdle","RifleADS","PistolIdle","PistolADS","KnifeIdle","FlashlightIdle","FuelIdle","JournalOpen","JournalReading","JournalClose","RifleReload","PistolReload","KnifeAttack"]
			for clip in list:
				var max_wrist:=0.0;var max_twist:=0.0;var max_forearm:=0.0;var max_step:=0.0;var previous:Dictionary={}
				var animation=ap.get_animation(clip);var frames=ceili(animation.length*30)
				ap.play(clip)
				for frame in frames+1:
					ap.seek(animation.length*frame/frames,true);ap.advance(0);sk.force_update_all_bone_transforms()
					for side in ["Left","Right"]:
						var h=sk.find_bone(side+"Hand");var f=sk.find_bone(side+"ForeArm");var u=sk.find_bone(side+"Arm")
						var neutral=sk.get_bone_global_pose(f).basis*sk.get_bone_global_rest(f).basis.inverse()*sk.get_bone_global_rest(h).basis
						var q=(sk.get_bone_global_pose(h).basis*neutral.inverse()).orthonormalized().get_rotation_quaternion();if q.w<0:q=-q
						var axis=(sk.get_bone_global_pose(h).origin-sk.get_bone_global_pose(f).origin).normalized()
						max_wrist=maxf(max_wrist,rad_to_deg(q.get_angle()));max_twist=maxf(max_twist,twist(q,axis))
						neutral=sk.get_bone_global_pose(u).basis*sk.get_bone_global_rest(u).basis.inverse()*sk.get_bone_global_rest(f).basis
						q=(sk.get_bone_global_pose(f).basis*neutral.inverse()).orthonormalized().get_rotation_quaternion()
						max_forearm=maxf(max_forearm,twist(q,axis))
						var local=sk.get_bone_pose_rotation(h)
						if previous.has(side):max_step=maxf(max_step,rad_to_deg(local.angle_to(previous[side])))
						previous[side]=local
				check(max_wrist<49 and max_twist<1.1 and max_forearm<80.1 and max_step<55,"%s %s %s bend %.1f / wrist twist %.1f / forearm %.1f / step %.1f"%[variant,mode,clip,max_wrist,max_twist,max_forearm,max_step])
			model.free()
	var pickup:WorldItemPickup=load("res://scenes/objects/items/weapon_pickup.tscn").instantiate()
	pickup.setup_spawn({"item_type":&"kitchen_knife","item_state":{},"transform":Transform3D.IDENTITY});root.add_child(pickup)
	var model:Node3D=pickup.get_node("Model");var bounds=AABB();var first=true
	for mesh:MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		var part:AABB=(model.global_transform.affine_inverse()*mesh.global_transform)*mesh.get_aabb();bounds=part if first else bounds.merge(part);first=false
	var collider:CollisionShape3D=pickup.get_node("CollisionShape3D")
	check(model.find_children("*","MeshInstance3D",true,false).size()==4 and absf(bounds.size.z-.3)<.001,"supplied Bornx knife has four material parts and 30 cm length")
	check(AABB(collider.position-collider.shape.size*.5,collider.shape.size).encloses(bounds),"new knife pickup collider encloses the actual blade and handle")
	pickup.free()
	print("ANATOMICAL JOINT CHECKS ",checks," FAILURES ",failures);quit(1 if failures else 0)
