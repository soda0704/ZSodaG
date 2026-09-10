# Death and radiation prototype

The server owns health, death, dose and respawn. PlayerSurvival sends state over
the reliable authority-only channel, including periodic state for late joiners.
Clients cannot apply damage or revive themselves. Health/dose are session state;
loading a checkpoint starts alive and healthy.

- 100 health. Landing impact is measured before move_and_slide, with moving-floor
  velocity taken into account. Up to 11 m/s is safe; 22 m/s is lethal at full health.
- More than 3 seconds of descending freefall kills even without landing.
- Expedition bounds: Y below -160, or X/Z beyond ±240 relative to level root.
  Level 4's authored descent reaches approximately -144; legitimate shaft
  geometry is not clipped by the kill plane. Staging fallback bottom is -40.
- Death disables movement, interactions and inventory actions, stows the light,
  cancels pending battery replacement through the inventory revision, and shows
  the cause plus a four-second countdown. Pause menu remains accessible.
- Respawn uses the assigned base day-start marker (initial spawn outside V3).
  Equipment and shared quest progress are retained: this is explicitly a forgiving
  prototype rule, not corpse recovery or permadeath. HP/dose reset on respawn.

RadiationZone is attached to Level 2 Water/Central_Reservoir_Water at runtime.
It spans a 9 m horizontal radius, from 2 m below to 8 m above the water origin,
covering the inspection bridge but not neighboring floors. Intensity fades from
1 at the center to 0.25 at the edge. Dose rises by up to 18 points/s and decays by
9 points/s outside. Above 35 dose it damages health, including residual exposure
after leaving the source. The warning sign and colored light identify the source.
Rates and fall thresholds are prototype tuning values, not real radiation units.

Tests: tools/tests/survival_test.gd (optional -- visual), plus the host/client
day_two_network_peer.tscn test, which now covers replicated death, inventory lock,
respawn, and subsequent quest delivery. Tests use isolated save paths.
