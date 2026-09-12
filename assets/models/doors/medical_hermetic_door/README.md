# Medical section door

Source geometry: Medical_Hermetic_Door.blend. Original file untouched. World vertex positions and polygon count preserved. Frame remains 6 × 6 × 0.6 m as supplied.

Prepared Blender: Blender/Doors/Medical_Hermetic_Door/medical_hermetic_door_realistic_2k.blend.

Export: medical_hermetic_door.glb, embedded 2048px Base Color, tangent Normal and ORM (R occlusion, G roughness, B metallic), two atlases. MEDICAL SECTION lettering is part of the frame texture on both sides. Indicators use a separate emissive material.

MedicalHermeticDoor origin is at floor centre. LeftLeaf and RightLeaf are independent children. Move each along local X by -2.51 m / +2.51 m to clear the opening. Godot import and movement checked with GLTFDocument. Gameplay, collision and animation are supplied by the game.

UVs checked: no positive-area triangle overlaps within either atlas. Export triangulates original polygons for tangent compatibility. Cameras and preview lighting are excluded.
