# Rebuilt NorthernLab exterior

Authored locally in Blender for NorthernLab, 6 November 2026. The previous envelope and its source files are retained separately. Dimensions follow `blender/arctic_base_exterior_shell/reference_measurements.json`; no interior layout changes.

Blue painted metal PBR source: **Blue Metal Plate**, Rob Tuytel / Poly Haven, https://polyhaven.com/a/blue_metal_plate . Licence: **CC0**, https://polyhaven.com/license . Downloaded 2K maps are in `pbr/`. Pale paint is a colour remap of the scanned diffuse, not a new scan. Normal and roughness remain aligned with the same scanned surface; the Godot wall shader offsets all three maps together.

Snow on the roofs uses the project's user-supplied Snow006 material. Its existing source and licensing information remain applicable. Antenna meshes are reused from the project's existing `selected_antennas_reduced.blend`; no new licence is inferred for those assets. All newly constructed walls, roofs, flashings, canopy and gate geometry were authored for this project.

Blender source and repeatable authoring scripts: `blender/arctic_base_rebuild/`. Run `author_rebuild.py`, then `finish()` in its namespace, then import into Godot and run `tools/authoring/connect_rebuilt_shell.gd`. Keep the checked-in import setting disabling lossy mesh compression for this envelope: it preserves coincident borders across material surfaces. Automatic LODs and shadow meshes remain enabled.

The garage shutter is separate because its existing cooperative controller, AnimationPlayer, handles and moving collision belong to `scenes/objects/garage/garage_gate.tscn`. The visual scene hides the former blockout, retains its named state nodes and mounts `garage_shutter.glb` inside the existing ClosedState.
