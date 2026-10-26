# Loading-screen media

User-supplied sources, kept unchanged outside the project:

- `E:/Downloads/Atom Loader.json` — Lottie `atom loading v2`, Sean Geoffrey Caare (source metadata). A copy is `atom_source.json`.
- `E:/Downloads/Всякая хуйня для игры/1024_prob4-vhs.mp4` — 1280×720, 30 fps.
- `E:/Downloads/Всякая хуйня для игры/Звуки/NorthernLab.wav` — NorthernLab, Александр Скворцов (source metadata).

`tools/authoring/prepare_loading_media.py` renders 57 transparent 160px atom frames into one atlas. The original paths and timing are retained; visible black fills become warm white for the dark interface. Godot's native AnimationPlayer plays the texture track at 30 fps over 1.9 seconds. There is no Lottie runtime plugin.

`vhs_01.ogv` is silent Theora, 30 fps, 14 seconds. A one-second end/start dissolve is baked into the video; it does not reverse the footage. Both the absence of an audio stream and the player's muted volume prevent its original soundtrack from playing.

`assets/audio/music/loading_northernlab.ogg` uses source 00:28–01:16, with a three-second tail/head overlap, producing a 45-second Vorbis loop. Its native import loop is enabled. The loading scene plays this separately on Music, with entry/exit fades; it stops when the cover closes.

The editable layout and copy live in `scenes/ui/loading_screen.tscn`. The `videos` array currently contains one entry; add the other four prepared videos there when available. Tips are five Inspector-editable LoadingTip resources; `{offer_item}`, `{interact}`, `{journal}` resolve through the existing input service. Scene generation is optional: `tools/authoring/author_loading_scene.py` overwrites this scene, including its layout and copy.

Tips advance automatically every five seconds, fading out for 0.15s and in for 0.25s. There is no visible tip count or switching instruction. Manual switching remains available without key repeat. Hidden screens stop video, music, atom animation and pending text transitions.

The separate native `scenes/ui/loading_render_warmup.tscn` prepares renderer features once in an isolated 16px viewport at application startup. Its scene is not artwork and does not alter the expedition's lighting. See `docs/technical/northern_lab_hud.md` for scene loading and readiness behavior.
