# Mountain panorama repair

The original 8192x4096 HDR source is imported at 4096x2048 using the native texture size limit. The 4K HDR texture supplies the sky and illumination; the source file is preserved.
A native Godot sky material blends a generated repair only inside the mountain hole.
The repair rectangle and feather are editable ShaderMaterial parameters in snow_exterior.tscn.
No per-frame script edits the sky, lights or textures.

Tool: built-in image_gen via the imagegen skill.
Input: a PNG inspection export of alpine_overcast_panorama.exr.
Output: alpine_panorama_repair.png (1774x887); its lower resolution applies only to the small repair rectangle, not the entire sky.

Prompt: Edit the existing 2:1 equirectangular panorama. Preserve full-frame layout,
projection, skyline, mountain positions, cloud lighting and colors. Fill only the
bright sky-colored triangular holes near the center with continuous blue shaded
snowy mountain faces matching adjacent rock and snow. Preserve the remaining
panorama and its wraparound edges. No additional peaks, changed weather or text.

The original mountain attribution remains in mountain_source_LICENSE.txt.
