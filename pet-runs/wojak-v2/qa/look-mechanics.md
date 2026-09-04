# Wojak look mechanics

Wojak is a face-only, hand-drawn humanoid head with no body or props. The lower edge and overall head size stay anchored. The eyes lead each look: the pupils and eye apertures shift together, eyelids and eyebrows reshape subtly, then the head turns or pitches only enough for the nose, cheek, ear visibility, and jaw contour to reinforce the gaze without stretching the skull or changing the familiar expression style.

Motion budget: each 22.5-degree step makes a small, even change in pupils, eyelids, brows, nose placement, cheek/ear visibility, and restrained head pitch/yaw. Adjacent poses keep the same scale, baseline, line weight, palette, and facial proportions. No whole-sprite rotation, broad raster warp, body, props, shadows, effects, text, or scenery.

Cardinal pose families:

- 000 up: pupils and eye apertures lift; upper eyelids open slightly; eyebrows lift; chin and lower head remain anchored; the nose stays centered with a subtle upward head pitch.
- 090 screen-right: pupils, eye apertures, and nose tip move clearly to the image-right side of head center; the image-right cheek contour becomes slightly more prominent while the opposite ear/cheek recedes.
- 180 down: pupils and eye apertures lower; upper eyelids descend; eyebrows settle; a restrained downward head pitch brings the nose and gaze below center while preserving skull shape.
- 270 screen-left: pupils, eye apertures, and nose tip move clearly to the image-left side of head center; the image-left cheek contour becomes slightly more prominent while the opposite ear/cheek recedes.

Diagonals interpolate both axes continuously between these four families. The 157.5-to-180 and 337.5-to-000 boundaries must be one ordinary step with no scale pop, registration jump, expression reset, or reversal.
