# Prototype weapons and ammunition

Original Blender 5.1 models: assets/models/weapons/{pistol,m4a1,kitchen_knife,
rifle_magazine,pistol_ammo}.glb. Editable .blend files are in the adjacent source
folder, excluded from Godot import. Rebuild with tools/build_weapon_models.py.
Journal pictures are renders of these same models, not generated concept art.

No range, targets, or dispensers are installed in the playable level. Test-only
targets are instantiated by weapons_test.gd. Level 0 has exactly one of each:

- Pistol: garage service bench (-30, 1.2, 7.25).
- M4A1: technical maintenance bench (-7.35, 1.25, 22.5).
- Kitchen knife: living-area dining table (15, 1, -3.5).
- Two 12-round pistol ammo pickups and two 30-round rifle magazines nearby.

The pistol has a 12-round magazine, semi-auto fire, and a 1.35-second reload.
M4A1 has 30 rounds, automatic fire at a 0.1-second interval, and a 2.1-second reload.
Reserve ammunition is finite, replacing the original infinite-reserve prototype.
Pistol reload inserts only missing rounds. Rifle reload selects the fullest spare
magazine and returns the old magazine if nonempty; repeated reload cannot destroy
usable ammunition. Reserve limits: 240 pistol rounds, 10 rifle magazines.
Death or weapon changes cancel pending reload. Checkpoint load also cancels reload,
preserving magazine and reserves. Partial magazines survive dropping/picking up.

LMB / R2: attack. R / D-pad Up: reload when a weapon is held, otherwise replace
flashlight battery. G: drop the held item. Weapons use the existing single hand
slot, with flashlight pocketed. Server owns cadence, ammunition and hit checks;
friendly fire is disabled. Knife reach is 2 m. Effects and reload movements are
procedural prototype animations, without character hand animation or ADS yet.

Inventory checkpoints contain weapon_layout_version=1. Older checkpoints get the
new loot layout once; subsequent loads restore saved pickups without seeding again.
User-facing level labels use 0, 1, 2, 3, 4. Legacy Floor_Minus resource/node paths
and negative world-space Y coordinates remain unchanged for compatibility.

Checks: weapons_test.gd (optional -- visual), base_gameplay_controller_test.gd,
and host/client day_two_network_peer.tscn. The network test includes client fire
and finite-ammo reload in addition to prior survival and quest checks.
