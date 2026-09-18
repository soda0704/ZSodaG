extends RefCounted

static func try_step(body: CharacterBody3D, delta: float, height: float) -> bool:
	if not body.is_on_floor() or body.velocity.y > 0.1:
		return false
	var motion := Vector3(body.velocity.x, 0, body.velocity.z) * delta
	if motion.length() < 0.001:
		return false
	var hit := KinematicCollision3D.new()
	var blocked := body.test_move(body.global_transform, motion, hit)
	if not blocked:
		return false
	# A capsule or box touching the top edge of a short riser reports a mixed
	# normal, so do not classify the contact from its normal alone. The raised
	# forward test below rejects tall walls while the landing normal still
	# filters out non-walkable surfaces.
	# A step is a short vertical lift over the blocking face, followed by a
	# normal horizontal move and a downward floor search. Keep a small margin
	# so the capsule is not left touching the riser.
	var raised := body.global_transform
	var lift := height + body.safe_margin
	# Do the clearance check at the raised position. Sweeping the capsule
	# upward from the floor makes the riser itself look like an obstruction and
	# rejects every real step before we ever test the top surface.
	raised.origin.y += lift
	if body.test_move(raised, Vector3.ZERO):
		return false
	if body.test_move(raised, motion):
		return false
	raised.origin += motion
	var down := KinematicCollision3D.new()
	if not body.test_move(raised, Vector3.DOWN * (lift + 0.12), down):
		return false
	if down.get_normal().y < cos(body.floor_max_angle):
		return false
	var landing := raised.origin + down.get_travel()
	# Vehicles can already be a few centimetres above the floor because their
	# box body is snapped from its underside. Keep the guard small enough for a
	# genuine low ledge while still rejecting a same-level contact.
	if landing.y - body.global_position.y < 0.001:
		return false
	body.global_position = landing
	body.velocity.y = 0
	body.apply_floor_snap()
	return true
