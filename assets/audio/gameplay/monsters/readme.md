# Monster audio clips

Short mono PCM16 / 32 kHz clips prepared offline from recordings already in this project. No external sound pack was added; this processing does not change or establish the rights to the source recordings.

Sources under `assets/audio/gameplay`: `tail.ogg`, `slasher.ogg`, `smily.ogg`, `breath_short.ogg`, `impact_concrete.ogg`, `floor_0.ogg`, `metal_0.ogg`, `snow_0.ogg`. Head vocal texture derives from smily, evolution from tail; the original three retain their own vocal sources. Attack preparation combines breath and vocal texture, misses use breath, contacts use concrete impact. Floor/metal/snow foot contacts are shortened and varied separately for head and evolution.

Regenerate from repository root:

```powershell
python tools/authoring/author_monster_audio.py
```

Dependencies: Python, numpy, scipy, soundfile (libsndfile). The script can use a local soundfile installation in ignored `tools/.local/monster_sound/python`, or a normal Python environment. It trims active source regions, resamples, filters, changes playback rate, layers existing recordings, fades edges and limits peaks. `authoring_report.json` records duration, peak and RMS for all 53 clips. Original recordings remain unchanged. In-game playback uses the authored WAV resources; this Python pipeline does not run at runtime.

Profiles are in `assets/config/monsters/audio`; presentation and occlusion are described in `docs/technical/audio_mix.md`. Replacing a model does not require regenerating these clips. Adjust its profile, walk animation and normalized foot-contact phases in the editor.
