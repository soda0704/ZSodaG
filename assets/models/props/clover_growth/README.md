# Clover growth models

Prepared from the user-supplied plant_set_7_AM226_Archmodel-28c269e9-textures.zip (Evermotion). Original source URL and metadata: info.json. The archive contains no explicit licence notice; none is inferred.

Native scenes and meshes: scenes/objects/base/plant_stages. Live stages 1–7 use source mesh IDs 027, 013, 011, 020, 009, 006, 030 respectively. Dead stages 1–5 use 018, 017, 002, 016, 015. Dead stages 6 and 7 use the bent DeadSunflower3 and straight DeadSunflower2 from the second archive. Original photo planes, UVs and colours are retained; transforms are corrected and scaled per authored stage. Early dry states are enlarged slightly and use a lighter dry tint so their source stems remain readable through glass. No runtime mesh construction is used. The two late dry flower heads gain one native crossed surface; their stems remain single. Other stages already have leaves in different planes, so they remain stationary without camera-facing billboarding.

Only the shared albedo/alpha atlas is required. It retains 4096 resolution to preserve narrow stems; materials use double-sided alpha scissor, with a lower cutoff and lighter dry tint for withered foliage. Unused source scenes and the original normal/translucency/duplicate albedo maps are omitted. Original source meshes have at most 276 triangles per selected live stage; dry flower cards have 4/6 triangles.

All visual choices (model, dimensions, rotation, material, stem geometry) are editable in the stage scenes. plant_growth_presentation.gd only selects visibility from the shared snapshot.
