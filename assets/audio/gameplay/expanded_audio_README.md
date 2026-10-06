# Additional gameplay recordings

Source: 22 user-provided files in `E:/Downloads`. Originals are unchanged.
Prepared clips are mono 44.1 kHz Vorbis quality 5, with peak headroom at 0.78.
Scene volumes provide the mix; breathing recordings were considerably quieter
than the other sources and are normalized before mixing.

## Loops

| Asset | Source | Extracted interval | Equal-power seam |
| --- | --- | --- | --- |
| wind | ветер.ogg | 0.5–89 s | 0.8 s |
| blizzard | буря.ogg | 0.5–61.5 s | 0.8 s |
| generator | генератор.ogg | 1–59.5 s | 0.25 s |
| ventilation | работающая вентиляция.ogg | 1–61 s | 0.8 s |
| snowmobile_idle | холостой ход.ogg | 0.4–11.7 s | 0.18 s |
| snowmobile_snow | езда по снегу.ogg | 1.5–9.8 s | 0.25 s |
| breath_calm | спокойное дыхание.mp3 | 0.1–22.5 s | 0.12 s |

End/head crossfades are baked into the files; native Godot import looping is
enabled. Startup, shutdown, impacts, clicks, reloads and recovery breaths are
single events. Trailing silence is shortened and ending fades avoid hard cuts.
Battery insertion and reloads use pitch-preserving time compression to fit the
existing 1.1/1.35/2.1 second gameplay actions; the actions themselves are unchanged.

## Scene configuration

Current balance, startup movement locking, category sliders and room acoustics
are described in `docs/technical/audio_mix.md`. PlayerAudio now has a Node3D
root so its positional cues follow the player instead of the world origin.

- `scenes/objects/effects/base_ambience.tscn`: exterior wind, muffled sheltered
  wind and perimeter storm. ExteriorAcoustics tracks doorway crossings with two
  narrow AcousticPortal scenes, rather than broad indoor volumes. Initial spawn,
  teleport and movement beyond 3 metres use a single overhead collision probe
  to recognize shelter, including the helicopter; no per-frame occlusion rays.
  Near doors, portal crossings take precedence. Open door wind is a positional
  source; every 0.25 seconds while near an entrance a single collision ray checks
  its path to the listener, so closed internal doors/walls block direct wind.
  Closed sheltered wind uses the native MuffledWeather low-pass bus.
  Weather playback remains independent of the graphics fog setting.
- `scenes/art/base/technical/generator_room_art.tscn`: positional generator at the
  authored generator equipment; follows replicated main-breaker power state.
- `scenes/objects/effects/ventilation_audio.tscn`: six positional sources attached
  to existing floor-0 vent fixtures and floor-2 air scrubbers; fades with power.
- `scenes/characters/player_audio.tscn`: accepted pickup, battery action and
  flashlight toggle cues follow authoritative events. Breathing is local only.
  Short/long recovery is selected at the end of a run (threshold 3 seconds),
  with 6/12 second recovery envelopes and a quiet calm loop. Restarting a run,
  death, sleep or entering a vehicle fades breathing out.
- `scenes/characters/weapon_controller.tscn`: reload and empty-trigger streams;
  impact resources choose snow, metal or concrete using collision-ancestor
  `impact_surface` / `footstep_surface` metadata and Terrain3D classification.
  Damageable actors and knife strikes do not trigger bullet surface recordings.
- `scenes/objects/vehicles/snowmobile.tscn`: ignition overlaps the idle/driving
  mix near its end; loops crossfade with speed and fade out under shutdown.
  Fuel exhaustion and driver exit use the same shutdown event; initial network
  snapshots of an occupied vehicle do not replay ignition.

`ice_slide.ogg` (скольжение на льду.ogg) is imported as a single-event resource,
but has no gameplay trigger: the project currently has no ice-sliding mechanic.
Do not substitute it for ordinary footsteps on snow.

All playback nodes, resource assignments and mix parameters are editable in
native scenes / Inspector. No lighting, environment geometry or animation
systems were generated for this audio integration.

## Validation

`expanded_audio_regression.gd` covers resource loop flags, reload timing, empty
triggers, accepted interactions, breathing transitions, indoor/power ambience,
  all four storm sides, and vehicle contact with actual Terrain3D snow.
`weapon_vehicle_audio_regression.gd` checks ignition overlap, dedicated idle,
acceleration, shutdown and late-observer state. Existing audio/graphics and
sprint/boost regressions also pass. Decoded Vorbis loop boundary sample changes
were checked against neighbouring sample changes for all seven new loops.
These are automated engine checks, not a two-player listening session; final
subjective volume balance should be assessed in play.
