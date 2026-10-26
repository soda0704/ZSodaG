# Pistol grip review — awaiting user selection

This isolated study uses the native tactical B world rig and the project's G17 mesh. A and B share the shooting-hand pose; the support hand differs in height and placement. Saved Grip animations use existing native bones. These scenes do not replace production animations or weapon gameplay.

Open review.tscn and run the current scene (F6). 1/2 selects the study; right mouse orbits; wheel changes scale; 3/4/5 shows right/left/top; 6 shows the body. Rendered comparison and full-resolution frames are in tools/.local/pistol-grip-review/.

Authoring: tools/authoring/build_pistol_grip_studies.gd. Rendering: tools/tests/render_pistol_grip_studies.gd. Neither study is anatomically or visually approved yet. Selection is followed by user-directed refinement, then fitting to the other native rig and separate first-person presentation.

Round 2: shooting wrist raised 25 mm relative to the same gun frame; index and thumb refitted to the physical trigger/upper grip. Separate fp_a/fp_b preview assets use the native FP arm rig. Key 7 toggles the FP preview. tools/.local/pistol-grip-review-r2 contains side and real Player-camera captures at FOV 75; comparison.png labels the cropped FP detail, while a-fp.png and b-fp.png preserve the full frame. Still awaiting user selection.

Round 3: accepted shooting-hand height is unchanged. The right PIP is raised by about 4.57 mm while preserving the DIP position and complete distal orientation, keeping the fingertip fixed (bake assertion <0.2 mm). Both support wrists move forward by 40 mm relative to their round-2 variants. Support phalanges use a wider wrapping arc instead of curling back into their own palm. The support elbow pole is fitted offline within the existing forearm/wrist limits. Updated grip markers agree with the preview poses. Images: tools/.local/pistol-grip-review-r3. Still awaiting visual approval.

Round 4: user selected B as the basis. Only LeftHandThumb rotations change; all 84 other native bones retain their saved poses in both world/FP rigs (thumb-only comparison against archived round 3, 0 failures). Support thumb points further forward along the left side of the pistol; its terminal advances about 46 mm in world and 36 mm in FP. review.tscn starts on B. tools/.local/pistol-grip-review-r4/comparison.png compares round 3 and 4. Thumb shape remains subject to user review.

User decision: B with the round-4 support thumb is accepted provisionally. Preserve these assets while the rifle is reviewed. Production animation integration and fitting to the other character remain separate follow-up work after item pose review.
