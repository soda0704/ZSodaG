# Expedition winch audio

`winch_gears_loop.ogg` is prepared from the user-supplied `shesterenki.mp3`.
The original recording in Downloads is unchanged.

- Original decoded duration: 28.813 s, with silence at both ends.
- Working source interval: 2.800–19.667 s.
- Seam: 350 ms raised-cosine crossfade, with correlation-aware energy compensation.
- Output: 16.517 s, mono Vorbis, 44.1 kHz, quality 5, approximately −25 dBFS RMS.
- Native Godot looping is enabled at offset zero in the import settings.

The decoded loop's boundary step is 0.000191; the 95th percentile of ordinary
adjacent-sample steps is 0.016981. The boundary follows the original waveform
continuously instead of inserting silence or an end fade.

`scenes/objects/elevator/expedition_winch.tscn` assigns this stream to its
positional `CabinMoving/TravelAudio`. The existing elevator state machine fades
it in during movement and out on arrival. The main base elevator keeps its own
recording. The short brake-preparation test also keeps its separate sound.
Winch movement, gates and preparation sounds use the existing `Machinery` bus,
so the game's machinery-volume control and world acoustics remain applicable.

`winch_brake_lever.ogg` uses the user-supplied
`mechanisms-blows-single-short-metal.ogg`: 0.814 s, mono Vorbis, 44.1 kHz.
Its audio packets are copied without re-encoding; the embedded Theora illustration
is removed. It is a one-shot sound on `BrakeAssembly/LeverAudio`, triggered only by
a new lever action. Native looping is disabled. Loading a saved armed position
does not replay the sound. The original file in Downloads is unchanged.
