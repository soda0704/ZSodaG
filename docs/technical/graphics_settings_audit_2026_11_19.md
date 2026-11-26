# Graphics settings documentation audit — 2026-11-19

| Setting | Runtime implementation | Audit result |
|---|---|---|
| Scale | Viewport.scaling_3d_scale | Actual 3D resolution; UI remains native. Bilinear retained for predictable low-end cost. FSR not enabled automatically. |
| MSAA | Viewport.msaa_3d; viewmodel viewport | Geometry edges only; cannot repair shadow-map texels. High preset uses 2x. |
| FXAA | Viewport.screen_space_aa; viewmodel viewport | Inexpensive spatial filter, with blur tradeoff. |
| ShadowQuality | Atlas 2048/4096/8192 and PCF quality | High now allocates higher positional resolution. Ordinary base lights no longer use mass PCSS. |
| ShadowDistance | WorldLighting sunlight distance | Sunlight only; interior distance is shortened to retain detail and reduce redraws. |
| AOQuality | environment_set_ssao_quality + Environment.ssao_enabled | Presets Off/Off/Low; custom Medium/High remain opt-in. |
| Glow | Environment.glow_enabled | Source-authored effect; fixed-frame cost was small. Preserved. |
| FogQuality | Volumetric buffer dimensions + authored enabled state | Internal setting, absent from menu. Does not control particle blizzard or regular fog. No forced volume pass in scenes without authored volumetric fog. |
| LOD | Viewport.mesh_lod_threshold | Only affects meshes with LOD data. 191 asset import files explicitly disable generation. Not a universal polygon-reduction slider. Do not bulk-enable on rigged assets without visual checks. |
| DecalDistance | Decal.distance_fade_begin/length | Real fade and culling; new dynamically added footprint decals receive settings through node_added. |
| TrackCount | SnowTracks.max_marks | Real bounded pool; visible difference only after enough footsteps. |
| MotionBlur | camera_post_process.gd | Project-specific camera effect; enabled in all three presets. Not built-in Godot motion blur. |
| FPS | Engine.max_fps | Frame cap; VSync may impose a second cap. |

Exact previous presets migrate, while custom selections and display calibration remain intact.

Sources:
- https://docs.godotengine.org/en/stable/tutorials/3d/lights_and_shadows.html
- https://docs.godotengine.org/en/stable/tutorials/3d/3d_antialiasing.html
- https://docs.godotengine.org/en/stable/tutorials/3d/resolution_scaling.html
- https://docs.godotengine.org/en/stable/tutorials/3d/mesh_lod.html
- https://docs.godotengine.org/en/stable/tutorials/3d/environment_and_post_processing.html
- https://docs.godotengine.org/en/stable/tutorials/3d/volumetric_fog.html
- https://docs.godotengine.org/en/stable/classes/class_decal.html
