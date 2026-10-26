# Rifle grip review — round 1

Pending user review. Native tactical B skeleton, M4A1 mesh, independent saved world and FP pose clips. No production gameplay or accepted pistol B pose is changed.

A: support wrist at foreguard z -0.170 m. B: support wrist 25 mm further forward. Right grip is shared; fingers use existing native bones. Wrist fitting is authored offline and baked into AnimationPlayer clips.

Run review.tscn: 1/2 variants, RMB orbit, wheel zoom, 3/4 sides, 5 top, 6 body, 7 FP. Actual production-camera screenshots (75 degree FOV and separate viewmodel pass) are in tools/.local/rifle-grip-review-r1. Camera framing is still a later refinement; these are grip proposals, not final acceptance.

Round 2: user preferred A. A support palm rotated 8 degrees clockwise from owner view about foreguard axis, wrist moved 8 mm toward owner. Support index/middle/ring/pinky flexion reduced from 65/70/30 to 60/61/25 degrees. Previous A scenes preserved in tools/.local/rifle-grip-review-r2. Pending review.

Round 3: A support thumb phalanges aligned in one relaxed direction along the foreguard toward the muzzle; only thumb posing changed. World close-ups and actual FP view rendered under tools/.local/rifle-grip-review-r3. Pending user review.

Round 4: world M4 stock heel positioned at native right shoulder surface. Both arms refitted to the same item-relative grip points; finger poses retained. FP framing remains separate and unchanged. Actual world/FP renders under tools/.local/rifle-grip-review-r4. Pending review.

Round 5: user requested stock contact further right. World stock and both hand targets shifted 30 mm to character right. Finger poses and FP presentation retained. Rendered in tools/.local/rifle-grip-review-r5; pending review.

Round 6: native elbow pad shell vertices rebound rigidly to existing pad bones; pad tracks follow elbow flexion independently of distal forearm pronation. No gameplay integration yet. Other bone poses verified identical to round 5. Screenshots in tools/.local/rifle-grip-review-r6.

Round 7 corrects round 6: user meant right elbow shell; left needs slight clockwise rotation and accurate seating. Both shells centered on native elbows with outward normals; left rotated 8 degrees. Rigid binding only for hard-shell dominant vertices; flexible mixed strap weights retained. Other 86 bone poses unchanged. Actual close-ups under rifle-grip-review-r7. Pending review.
