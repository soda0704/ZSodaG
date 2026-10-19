# Runtime polish — 19 October 2026

This pass preserves the simplified menu, common expedition save and the authored world lighting.

- Fuel station accepts a nonempty held canister from any visible side, within the existing host distance and line-of-sight checks. The hint reads «Залить топливо». Generator usage is 0.015 L/s (previously 0.01).
- Loose flashlights can be exchanged, dropping the previous lamp with its charge and fault state. Mounted charged M4 lights give R to ammunition; depleted lights give R to battery replacement. The wiring camera has an authored centred beam, enabled only by the actual working flashlight and consuming its battery.
- Sleep uses the supplied normal bed model, enlarged 18% to a 2.44m frame for the 1.824m character plus mattress clearance; a separate matte material retains the original albedo and normal maps. Both beds run along the wall; obsolete bunk blockouts are removed. One interaction lies down after the day's tasks, with the existing sleep consensus and save on morning. A waiting coop player can get up. No separate readiness UI remains.
- Garage handles are fixed to the side posts and remain reachable when the door is open. Solo needs one held handle; coop needs two distinct players and handles. Releasing interrupts an incomplete hold; the next hold closes the gate. Host validation, live heartbeat and collision checks remain.
- Locked elevator destinations, unpowered terminals, missing fuse/corpse actions and non-actionable key prompts no longer advertise E. The in-flight ramp's bare E opens the existing lobby. Main-breaker failure says «Нет энергии».
- Vault key extraction requires a 1.35-second UI hold and at least 1.25 seconds on the host. Release cancels; direct interaction packets cannot bypass the hold. The hub action has an explicit frame. Terminal clicker, shared operator lease and other applications are retained.
- Generator alcove has standard and red emergency lamps in the existing bounded lamp pool. Snow is lowered underneath the room floor in the native Terrain3D height map, with no interior shader discard or outside hole. Solar-cell readability is a textured material emission of 0.015, with no new sunlight receiver membership. Arrival platform/ramp/helicopter meshes receive the separate shadow-caster layer 15; this survives the real player camera excluding layers 18/19. Sun colour, energy, direction, ambient and fog retain their authored values.
- Menu highlighting follows the mouse. Feedback is a separate lower-right button above the bottom rail. Character selection has a dimmer backdrop, lower preview lighting, key-light shadows, 8x MSAA and 2x supersampling capped at 2160px tall, using original textures. A transparent black clear colour and premultiplied-alpha compositing remove the white silhouette fringe. The dropdown has its own opaque dark styles.
- Elevator inner corner covers and entrance jamb liners cover the imported 0.875m guide columns while keeping the cabin exterior footprint. A welded mesh enclosure with solid wall collisions, entry returns and canopy surrounds the surface shaft. Its only entrance is protected by the existing landing door; the enclosure stays on floor zero when the cabin descends. Floor buttons and their colliders are round. Western orange paint and its hub colour marker are yellow. Large snowmobile/garage headings are hidden. A native sign beside the winch explains day 7 and `/cave entry`.
- All three incubator pushbuttons share one interaction volume and one daily watering action. The label is centred above them; the seed packet starts higher between the kitchen knives.
- The existing arrival cover now animates and introduces the journal using its actual binding. Resource loading is threaded; scene instantiation remains on the main thread.
- New installations start with a conservative graphics recommendation based on adapter/resolution, capped at 60 FPS. After a 5-second gameplay warm-up, 240 measured frames per round determine whether rendering scale/geometry budgets need lowering; at most five reductions, minimum 50% rendering scale. The P90 measurement and resulting profile are stored in the existing settings. Manual graphics edits cancel calibration. Quality → Recommended → Pick starts it again. This is a target, not a guarantee on every CPU/GPU or every scene; authored lighting is not recalibrated. Automatic reductions never change shadow distance/quality, AO, fog or GI.
- Gunshots emit a short small flame and low-opacity powder gas, using native particle resources shared by both character variants and first/third-person views. Existing muzzle-light energy is reduced.
- `/clear` clears command output and submitted-command history, leaving clickable command suggestions in a separate panel.

## Navigation

Gameplay loads `assets/navigation/containment.tres` (191 polygons); it no longer parses/render-reads meshes or bakes on game startup. After changing biocontainment collision/layout, regenerate offline:

```
tools/.local/godotsteam-editor/godot.exe --headless --path . --script tools/bake_containment_navigation.gd
```

The authoring command may emit the mesh-parser warning while baking CSG offline; this work does not run in gameplay. Recheck monster routes after regenerating.

## Verification

- Fuel station: 31 checks including side approach, obstruction, capacity, invalid state and saved gauge values.
- Gameplay polish: 20 checks including direct sleep/cancel, interior wake point, garage open/close, flashlight swap, R priority, clear and conservative recommendations.
- Terminal quest: 39 checks including too-short hold rejection and saved/reopened quest state.
- Graphical clicker terminal: 23 checks including real mesh UV mouse input, reopening and common persistence.
- Wiring: 47 checks; mounted light: 22; offhand items/light: 104.
- Real ENet host/guest quest + garage/sleep: 18 host and 14 guest checks.
- Menu integration and audio/graphics regression suites.

Visual captures are produced in `tools/.local/fix-*.png`. Runtime baking warning is absent in the normal base and ENet logs. Some existing test teardown RID/resource warnings remain; these are not the navigation warning.

## Visual follow-up

`tools/tests/visual_polish_followup_regression.gd` checks preview sampling/compositing and dropdown contrast; actual player-camera shadow eligibility; unchanged authored world energy; native terrain heights inside/outside; matte bed scale; all four cabin corner sight-lines; static surface-guard collisions and the landing door with the cabin absent/returned. Captures: `tools/.local/review2-*.png`.
