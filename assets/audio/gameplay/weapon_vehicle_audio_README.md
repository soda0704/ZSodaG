# Weapon and snowmobile audio

Converted from the four user-supplied recordings. Original files in Downloads are unchanged.

| Game asset | Source | Preparation |
| --- | --- | --- |
| `m4a1.ogg` | `m4a1.m4a` | Single shot, leading silence removed; 0.270 s. |
| `pistol.ogg` | `Пистолет.mp3` | First shot extracted from the three-shot recording; 1.350 s. |
| `snowmobile_start.ogg` | `Снегоход заводится.mp3` | Starter and initial ignition extracted; 3.800 s. |
| `snowmobile_drive.ogg` | `Снегоход едет.mp3` | 150 ms equal-power seam crossfade; native looping enabled. |

All clips are mono Vorbis, 44.1 kHz, quality 5, for positional playback.
Gunshots and ignition have a short ending fade.

Weapon streams and spatial playback settings are editable in
`scenes/characters/weapon_controller.tscn`. Vehicle audio nodes and exported
idle/driving pitch and volume are editable in `scenes/objects/vehicles/snowmobile.tscn`.

The engine starts when a fueled snowmobile becomes occupied, crossfades into
the dedicated idle/driving loops, and plays shutdown on exit or fuel exhaustion.
Driving speed controls the blend and driving pitch. Snow contact has a separate
loop that plays only while moving over a snow surface. Ignition now locks movement
until the start recording finishes; see `docs/technical/audio_mix.md` for the
current bus routing, mix and startup settings.
