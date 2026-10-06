# NorthernLab background music

Prepared from the user-provided `E:/Downloads/NorthernLab.wav` (lossless source);
the accompanying MP3 is the same recording. Source files are unchanged.

Stereo 48 kHz Vorbis quality 6. Original duration: 233.2 seconds. A 3-second
equal-power end/head crossfade is baked into the 230.2-second loop; native
Godot looping is enabled in the import settings.

`scenes/objects/effects/background_music.tscn` is instanced under the existing
GameMenu autoload. One player persists across menus, lobby and gameplay without
restarting on scene changes. Inspector exposes volume (-20 dB) and fade-in
(2 seconds). The existing Music slider and Master settings control playback.
The menu background video is retained with its soundtrack muted to avoid overlap.
