# Supplied animation references

These JSON files contain sampled skeletal motion derived from the user-supplied glTF archives. The reference meshes are not used as player arms. Both native DanlyVostok skeletons retain their weighted bones and their own proportions.

- M4A1 Animated Low Poly by sycgff: https://sketchfab.com/3d-models/m4a1-animated-low-poly-91de835e74e24b65b69659bdbe392ea9 (CC BY 4.0).
- AnimatedPistol by JUST: https://sketchfab.com/3d-models/animatedpistol-e0bbe625b9504ed59db273c310e1cce7 (CC BY 4.0).
- Animated Knife by JUST: https://sketchfab.com/3d-models/animated-knife-7bee900b43f24ed9b3d48304362d5599 (CC BY 4.0).

Original attribution notices are retained beside the JSON files. Adaptations: skeletal sampling, canonical coordinate conversion, motion scale fitting, retiming to existing gameplay durations, anatomical joint limits, native finger flexion retargeting, and saved Godot Animation resources. Include these credits when distributing the derived animation assets.

Re-extract using Blender: `blender --background --python tools/authoring/extract_reference_motion.py`. This authoring-only step expects the supplied archives extracted into the ignored `tools/.local/pose-references/{rifle,pistol,knife_pose}` directories. Asset regeneration uses the checked-in JSON and does not require the archives or Blender.

The supplied book reference is a static mesh without bones or animation: *hands holding an a6 sized book* by omiyaio, https://sketchfab.com/3d-models/hands-holding-an-a6-sized-book-c714117a4543421983ff0c765886a025 (CC BY 4.0). It was inspected as a pose reference; its geometry is not used in the game.

The archive labelled as the canister reference is truncated. Only its license can be read; it identifies *Cast of Lincoln's Hand - Library of Congress* by Thomas Flynn. No geometry or animation was imported from that archive.
