# Rock geometry and textures

Source assets from Poly Haven, distributed under CC0:

- https://polyhaven.com/a/rock_face_01
- https://polyhaven.com/a/rock_face_02
- https://polyhaven.com/a/boulder_01

The glTF files, binary geometry and 2K texture maps are the original downloads.
The `cave_mesh.res` resources are reduced native Godot variants. The cave uses
approximately 5,042 / 3,694 / 1,032 triangles per instance respectively, rather
than the full source scans. `cave_material.tres` contains the local material tint.

The source geometry is retained for future art edits. The small rock details do
not replace the cave's structural walls. Gameplay colliders are closed convex
shapes; the structural cave and mouth use their saved triangle collision meshes.
