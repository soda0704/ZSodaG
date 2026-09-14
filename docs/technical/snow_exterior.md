# Snow exterior

The surface remains level 0 at its original coordinates. Lower floors were not moved.
`scenes/levels/snow_exterior.tscn` adds a 512 × 512 m Terrain3D landscape, snowy low-poly
pines and rocks, roof snow, daylight, and the user-supplied EXR panorama.

Terrain3D 1.0.2 stable is vendored under `addons/terrain_3d`, including its MIT license.
Source: https://github.com/TokisanGames/Terrain3D/releases/tag/v1.0.2-stable

Edit the four regions in `assets/environments/snow/terrain_data` with the Terrain3D
editor tools. Save the scene AND modified terrain regions. The shaft has a hole;
do not paint terrain over it. Runtime full-region collision supports players far
from the host camera. Outdoor sunlight uses render layer 19; held weapons use 20.
The console command `/outside` moves the caller beside the garage; `/level 0` returns.
The separate `/testroom` is buried at (180, -130, 180), outside the base interiors.

`tools/generate_snow_exterior.gd` is an explicit deterministic rebuild tool, NOT a
runtime generator. Running it overwrites authored terrain and exterior decorations.
Run with a graphical renderer (not headless: MultiMesh buffers need a real renderer):

    tools/.local/godotsteam-editor/godot.exe --path . --rendering-method gl_compatibility -s tools/generate_snow_exterior.gd

Regression/visual check:

    tools/.local/godotsteam-editor/godot.exe --path . -s tools/tests/snow_exterior_test.gd

The test uses an isolated save and writes overview/arrival screenshots to TEMP.
