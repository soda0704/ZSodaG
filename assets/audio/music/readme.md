# NorthernLab main-menu music

`main_menu.ogg` is prepared from the user-provided
`D:/Work/11/footage/Create_a_deeply_atmo_#2-1792512733821.wav`.
The external source is unchanged. Stereo 48 kHz Vorbis quality 6, 30 seconds;
native Godot looping is enabled in the import settings.

`scenes/objects/effects/background_music.tscn` is a child of the main menu,
not the persistent GameMenu autoload. It starts once on entering the menu,
continues across its pages and settings overlays, and stops when the menu
scene is freed. Returning from gameplay creates a fresh player.

Every menu entry starts at silence and fades in for 4 seconds to -6 dB,
including startup and returning from gameplay. The fade uses a smooth
amplitude curve; opening settings, changing pages, and looping the track
do not restart it. It uses the Music bus, sent to
Master, so the existing Music and Master settings control playback and mute.
The background video retains its visuals; its old audio track is removed
and video playback is also muted in the scene. The unused former
`northernlab.ogg` recording is removed.
