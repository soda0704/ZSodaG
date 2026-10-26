# Prototype character source

`scene.gltf` and `scene.bin` are the current prototype character supplied for the
game. It contains 409 vertices and a compact 32-bone deformation rig. The source
does not contain animation clips.

`scenes/characters/player.tscn` instances this model directly for the remote-player
visual at a real-world height of about 1.79 m. A lightweight procedural component
animates the existing arm, leg and spine bones for walking, sprinting, jumping and
crouching. The local first-person player does not render its own body.

When authored animation clips arrive, they should replace the procedural poses
without creating a second player scene or a second character model.
