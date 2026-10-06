# Sound mix

The Audio settings tab retains Master and Music and adds Effects/interactions,
Weapons, Vehicles, Machinery, Ambience, Breathing and RoomReverb. Values are
saved through the existing GameMenu settings file. Category buses are authored
in `default_bus_layout.tres`; world sounds feed a shared World reverb/filter,
while music and subjective breathing bypass it.

AudioMixController blends room wet level using existing doorway/geometry
acoustics, without room dome volumes or changes to lighting. Reverb defaults to
6% wet (maximum 12% at 100% RoomReverb), with a small damped room. Outdoors is dry
with a gentle 10 kHz high-frequency cutoff. The Vehicles bus has a 2.4 kHz filter.
Unassigned positional effect sources are routed to Effects; explicit Inspector
bus assignments are preserved.

PlayerAudio is now Node3D. Its positional pickup, battery and flashlight children
inherit the player's world transform, fixing their previous placement at the
world origin. Pickup/click gains are raised; gunshots are reduced from -12 to
-28 dB. Recovery breathing is -20 dB instead of -17; calm remains -30 dB.
Generator gain is -8 dB, unit size 8 m and maximum distance 40 m; native vent
instances keep their own quieter -27 dB override.

Snowmobile ignition now locks movement on the server for the recording duration.
Remaining ignition time travels in existing vehicle state snapshots; late
observers seek into an in-progress startup or skip completed ignition.
Idle stays the dominant bed at -11 dB and pitch 1.0–1.096. The driving layer is
-23 dB, pitch 0.66–0.756, filtered and blended in gently. Startup is -13 dB and
overlaps idle. Exiting or losing fuel still fades the loops under shutdown.

`audio_balance_startup_regression.gd` checks source transforms, category controls,
bus mute independence, indoor/outdoor DSP, startup movement locking, fuel and
startup replication. Existing audio events and sprint/boost regressions pass.
Final subjective tone/volume should be heard in gameplay, especially at the
driver seat, with current Master and category settings.
