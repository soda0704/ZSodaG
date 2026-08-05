# Prototype character source

`scene.gltf` and `scene.bin` are the original character files supplied for the
gameplay prototype. The mesh contains 1,832 vertices, but the export also carries
an oversized 320-joint rig and no animations.

`character_visual.res` is the runtime version. It keeps the bind-pose mesh and
material while stripping unused joints and weights. `scenes/characters/player.tscn`
uses this resource only for remote-player visuals at a real-world height of about
1.78 m; the local first-person player does not render its own body. The `.res` is
self-contained and does not load the original GLTF or skeleton at runtime.

Regenerate the optimized resource after replacing the source export:

```text
godot --headless --path . --script res://tools/build_prototype_character.gd
```

An animation-ready export should replace this temporary static visual later.
