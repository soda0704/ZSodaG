# Snow exterior

The base and underground floors retain their coordinates. The exterior now has a
1024 × 1024 m Terrain3D landscape, uneven steep slopes, pine groups, six rock mesh
variants with collision, and sixteen distant background ridges. Snow on rocks is
part of their slope-dependent material, replacing separate spherical snow caps.
The existing sky panorama and daylight remain.

Terrain3D 1.0.2 stable is vendored under `addons/terrain_3d`, including its MIT license.
Source: https://github.com/TokisanGames/Terrain3D/releases/tag/v1.0.2-stable

Edit the sixteen regions in `assets/environments/snow/expanded_terrain` with the Terrain3D
editor tools. Save the scene AND modified terrain regions. The shaft has a hole;
do not paint terrain over it. Runtime full-region collision supports players far
from the host camera. Render layer 18 receives snow decals, outdoor sunlight uses
layer 19, and held weapons use 20. Keep these layers separate. Terrain3D's internal
high layer bit is preserved. `minimum_view_distance` exposes the 2600 m camera
clipping distance needed by the background ridges.
The console command `/outside` moves the caller beside the garage; `/level 0` returns.
The separate `/testroom` is buried at (180, -130, 180), outside the base interiors.

Indoor/outdoor camera environments are now managed by `EnvironmentZoneController`
and explicit `indoor_environment_zone` Area3D volumes. Roof snow is generated only
for visible CSG roofs in `exterior_snow_roof`; hiding an art/blockout branch must not
leave its snow cap floating above the map.

## Editing the expanded exterior

- Edit `Landscape` MultiMeshes and `RockAndTreeCollision` together when moving
  trees/rocks. Ridge meshes are in `DistantMountains`; their materials and meshes
  are in `assets/environments/snow`. They are saved assets, not runtime scenery
  generators. Background mountains are scenery beyond the playable valley.
- The old `terrain_data` directory is retained but not loaded by the new scene.
  Central terrain control maps, including the shaft hole, were preserved.
- `scenes/objects/lobby/arrival_site.tscn` owns the imported heliport, its concave
  collider, metal ramp, existing Chinook instance and arrival markers. Pad center:
  (-125, 8, 95), about 157 m from the base origin. The 3 m wide ramp exits east
  onto a graded snow corridor toward the base. Ribs are visual; walking collision
  is a continuous slope. Landing uses the existing readiness/fade flow and markers.
- The landed helicopter ramp starts open; its logic and animations remain in the
  existing Chinook scene.

## Temporary snow tracks

`SnowTracks` runs `scripts/effects/snow_tracks.gd`. It samples local/replicated
players and snowmobiles and emits native Decal scenes from `scenes/objects/effects`.
Textures, sizes, receiver masks and fades are editable scene resources. Foot
spacing, ski separation, vehicle offsets, contact tolerance, count and lifetime
are Inspector settings.

Contacts must hit Terrain3D close to the actor's feet. Metal, indoor floors,
airborne movement, flight, noclip, dead players and seated drivers do not emit
footprints. Large position jumps reset spacing. Stationary actors add nothing.
There are at most 512 marks per client, lasting 75 seconds with a final 10-second
fade. Oldest marks are replaced at the cap. These are cosmetic surface marks,
not terrain deformation or saved evidence. Clients generate them locally from
actor positions; exact placement/history is not synchronized or restored on join.

## Validation

    tools/.local/godotsteam-editor/godot.exe --path . -s tools/tests/snow_expansion_test.gd

This loads the real level without persistent progression, checks both arrival
markers, moves the player body up/down the ramp and along the route to the base
without jumping, and checks
footprint surface filters, vehicle tracks, count limits and expiration. A graphical
run saves `user://snow_expansion_tracks.png`; failed checks exit nonzero.

The scene was visually checked using Forward+. A live two-computer Steam co-op
session and lower-end GPU performance still need manual playtesting; this test
does not simulate network transport or Steam input.

## Heliport attribution

This work is based on “Heliport helicopter-45MB” by adventurer, licensed under
CC-BY-4.0, from the user-provided archive. The scene scales the model and adds a
separate ramp and collider. Original model files and `license.txt` remain in
`assets/models/environment/heliport`.

- Model: https://sketchfab.com/3d-models/heliport-helicopter-45mb-0067900e00954ba6b519078a36c90936
- Author: https://sketchfab.com/ahmagh2e
- License: https://creativecommons.org/licenses/by/4.0/
