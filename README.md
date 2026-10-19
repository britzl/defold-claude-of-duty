# Disclaimer

This project is a Defold take on the Call of Duty clone "Claude of Duty". This is an experiment to see how well Codex (GPT-6 Astra Extra High) can  convert the preexisting Kaigen3D and Three.js versions to Defold. Not a single line of code is written by a human.

- Kaigen3D version
   - Source: https://github.com/Kaigen-Technologies/kaigen-claude-of-duty
   - Plyable: https://kaigen3d.com/demos/claude-of-duty/
- Three.js version: https://github.com/mshumer/Claude-of-Duty

- Playable HTML5 version: https://britzl.github.io/ClaudeofDuty/

# Defold Claude of Duty

Runtime-generated port targeting Defold 1.14.0. See [PLAN.md](PLAN.md).

The first plan step is implemented: a gameplay controller, six subsystem modules,
120 Hz fixed simulation, metre-based 3D physics with gravity -20.6 m/s², buffered
input, gameplay notifications, centralized damage, and separate camera/HUD
presentation. The full market layout is generated at runtime: a 104-metre
street, all 20 reference building footprints, five flank routes, the ruin yard,
far cross street and south gate passage. W2, E1 and E2 have connected upper
floors; E3 has an enterable ruined ground floor. Source-derived setbacks, balconies,
recessed windows, roof props, a pointed gate and the market dressing are generated too.
A swept kinematic capsule now supports walking, sprinting, tactical sprint,
sliding, mantling, leaning, jumping, crouching, prone movement, stairs and slopes.
The M4A1, MPX-9 and P-19 now have fixed-tick fire control, projectile ballistics,
reloads and generated viewmodels in an isolated render pass. Six runtime-generated,
25-bone soldiers patrol as two squads, share alerts, claim cover and coordinate
a rear-lane flank while firing physical rounds. Nearby player rounds and impacts
build suppression; enemies duck, recover and alternate hiding with peeks from
low cover. GPU-generated surface maps,
shared material lighting,
animated sun shadows, a procedural sky, height fog, tone mapping and bloom are
implemented. A runtime-generated sound bank now supplies weapon fire, reloads,
surface footsteps/impacts, movement foley and ambience through a bounded spatial
audio mixer.
The combat HUD now includes a compass, generated minimap, damage direction,
health bar and killfeed. Escape opens a pause menu with audio, display and
mouse controls; focus loss also pauses the encounter.

## Ballistics and regional damage (2026-10-19)

Step 8 adds deterministic material deflection and reconciles damage with the
references. Soldier hits now use **4× head, 1× chest, .9× lower torso, .65× arms
and .7× legs**. Four new arm boxes follow the upper-arm and forearm bones. All
11 volumes use the authoritative pose, and the first volume struck selects
one damage application per actor per round. Damage/death events preserve
`region` and `part`; the combat module remains the sole health owner.

Each layer consumes `distance / material_depth` penetration power. Damage
retention is `max(.05, 1 - material_loss * distance / entry_budget)`, where
`entry_budget = material_depth * remaining_power_at_entry`. This replaces the
previous exponential approximation. Loss accumulates across fixed ticks;
overlapping solids consume power together and keep independent entry budgets.
Weapon damage, velocity, drag, penetration, range and quadratic falloff tuning
already matched the source and are retained. Falloff applies once using actual
travelled distance, including penetration and bends.

At an exit, two Gaussian samples scatter the direction by the material's
reference coefficient times the used budget fraction. Each round owns its RNG;
impacts do not consume weapon-spread, AI or presentation randomness. The rest
of that tick is re-queried from the exit, and tracer/suppression segments follow
the bend. No epsilon jump skips adjacent thin geometry. Speed is preserved by
deflection; gravity and drag continue normally. Six material entries and 128
live rounds per subsystem remain the bounds.

**Firing-origin rule:** rounds start at the collision-limited eye. Cover on the
aim ray is hit even if the independently rendered muzzle extends through it.
An obstruction that overlaps only the visual muzzle does not block a clear eye
ray. This intentionally retains crosshair aiming and does not make gameplay
depend on the interpolated viewmodel or its separate projection.

Bullet queries now refresh spatial bounds before reading moved hit volumes;
the previous ray API could miss a limb transformed earlier in the same frame.
The soldier adapter owns **66 hit volumes and 78 objects** for six actors,
adding 24 collision objects. Meshes, GPU buffers, joint palettes, draw calls,
render targets and audio banks are unchanged. Immediate-query cost still needs
sustained-combat profiling. Oriented box proxies, split arm segments, accumulated
travel and private RNG sequences are documented adaptations.

```sh
lua tests/ballistics_test.lua
lua tests/weapons_test.lua
lua tests/ai_test.lua
PYTHONPATH=automation-bridge-python python3 tests/ballistics_smoke.py
# Build release wasm-web with tests/ballistics_browser.project, then:
PLAYWRIGHT_MODULE=/path/to/playwright node tools/validate_ballistics_browser.mjs --bundle=/path/to/bundle
```

All **282 standalone checks in 30 Lua suites**, plus the **12 baseline-tool
checks**, passed. The shared fixture passes eight checks on Mac Metal and release
Chrome WebGL2/ANGLE Metal: six material lanes, repeatable scatter, multi-tick
penetration, all 11 real Bullet volumes in three poses, a lethal headshot,
production firing against cover, pause and three encounter resets. Reports are
under `build/ballistics-unit-validation`, `build/ballistics-native-validation`
and `build/ballistics-browser-validation`. The existing 13-check native player-health
fixture also passes, including hostile hits and blocked-round suppression. The
updated native soldier suite passes head/forearm/lower-torso shots, pursuit,
occlusion, room entry and eight replacements; its log is
`build/ballistics-ai-validation.log`. The unit matrix also checks all twelve
surfaces and three weapons, targets reached/missed after deflection, adjacent
thin geometry, per-region damage/ownership and falloff. Controlled reference
comparisons and sustained performance remain qualification work.

## Weapons and first-person animation (2026-10-19)

Step 7 adds generated arm meshes with **17 joints per arm**, body-fixed shoulders,
two-bone IK and jointed gloved fingers. The same two meshes serve all three weapons.
The rifle support hand wraps its handguard, the SMG uses its vertical foregrip,
and the pistol support hand cups the firing hand. Reloads visit the magazine,
withdraw below the frame, seat the replacement and operate the charging handle
or pistol slide. The firing index finger and trigger move together; selectors
follow the selected fire mode. Inspection, draw and holster have support-hand tracks.

Weapon recipes now include chamfered receivers and controls, open handguard
vents, rail teeth, stock pads, optic adjustment housings, folded sights, slide
serrations and an extractor. These remain bounded procedural approximations of
the source models, with visibly lower tessellation and detail density.

Camera-follow springs, layered idle sway, breathing, landing response and
figure-eight bob advance at 120 Hz. Bob follows actual footfall distance, so
pushing into a wall does not keep cycling it. Sprint/low-ready blend smoothly;
rendering interpolates fixed state without advancing animation. Pause freezes
both pose and reload time, inspection cameras/death stop the motion layer, and
teleports/restart clear follow history. A 120 ms outgoing-pose blend softens
inspection firing and reload-to-holster interruptions without delaying gameplay.

ADS now solves translation **after rotation and additive motion**. At full aim,
the sight remains on the camera axis at the weapon's eye relief. The collimated
dot projects that axis onto the optic plane; it does not drift with camera-follow
lag. The pistol dot is hidden while its slide is cycling or locked back. Existing
ammo ownership and the 81%/71% magazine transfers and 91.7% chamber beat are unchanged.

Arms use the existing weapon material/lighting functions and independent
viewmodel depth and AA pass. No render targets, atlas allocations or native
extensions were added. Weapons total **19,446 vertices** across 24 parts; the two
shared arms add **15,096 vertices** and 34 joint matrices in two palette uploads
per displayed frame. Combined vertex streams are **1,442,064 bytes** before engine
overhead. Including the unchanged 24 effect slots, the adapter owns 50 objects,
50 buffers and 35,406 vertices. The active viewmodel gains two draw calls. The
IK keeps wrists connected by allowing limited sleeve length correction on
extreme reload poses (maximum 1.162× in the sampled clip matrix). Normal hip/ADS
grips and all authored clips are checked for finite, connected joints.

Validation commands:

```sh
lua tests/viewmodel_test.lua
lua tests/weapons_test.lua
PYTHONPATH=automation-bridge-python python3 tests/viewmodel_smoke.py
# Requires Pillow:
PYTHONPATH=automation-bridge-python python3 tests/viewmodel_render_smoke.py
# Build release wasm-web with tests/viewmodel_browser.project, then:
PLAYWRIGHT_MODULE=/path/to/playwright node tools/validate_viewmodel_browser.mjs --bundle=/path/to/bundle
```

All 268 standalone checks across 29 suites passed, plus the 12 baseline-tool
checks. The shared fixture passed 19 checks and saved 19 captures on each of
Mac Metal and release Chrome WebGL2/ANGLE Metal. Seven native frozen views repeat
exactly; arm-material, indoor-lighting and weapon-AA toggles change the expected
pixels and restore exactly. The unit matrix covers geometry/winding, singular IK cases, connected joints,
ADS/dot alignment under motion, magazine/hand attachment, stride/lag, interruption,
pause and 30/60/144 FPS equivalence. Native and browser fixtures use production
input, firing, reload and switching code and capture hip/ADS/fire/reload/charge/
inspect for all three weapons plus an indoor view. Results are under
`build/viewmodel-unit-validation`, `build/viewmodel-native-validation`,
`build/viewmodel-browser-validation` and `build/viewmodel-render-validation`.
Seven matching Three.js stills are in `build/viewmodel-threejs-validation`.
They support visual review; differing lighting/materials, reduced geometry,
controlled reference motion, Kaigen comparison and sustained performance remain
qualification work. No exact cross-engine appearance or performance claim is made.

## Player health and suppression (2026-10-19)

Player health now recovers after **4.6 seconds** without damage, ramping over
**0.55 seconds** to **34 HP/s**. New hits restart the delay. Landings faster than
**15 m/s** cause **7 HP** damage per additional m/s, once per landing, through
the combat owner. Dead actors cannot heal.

Hostile rounds passing within **3.2 m** of the eye, visible nearby impacts,
hits and explosion events feed a bounded suppression pool. Segments, entry/exit
impacts and hits from one round contribute only their strongest stimulus.
Visibility checks start at the player's clear eye so rounds stopped inside a
wall cannot suppress through it. Player-fired rounds are excluded. Firing
origins are copied into damage notifications for camera/HUD direction.
Suppression decays at **0.62/s** and strengthens camera sway/impulses.

Below **36% health**, the scene gradually loses colour and gains a pulsing red
rim; below **18%** the state is critical. The double heartbeat envelope speeds
up from **1.05 to 2.05 Hz** with severity. The HUD displays `RECOVERING` during
regeneration. The treatment uses the existing composite in exposed linear HDR
before AgX, after temporal resolve; it adds no targets or draw passes and does
not affect scene exposure metering. Damage/pulse/recovery timers use fixed
simulation ticks. Pause, loading and inspection freeze progression; death stops
heartbeat/suppression/recovery and holds the death treatment; restart clears it.

`gameplay.snapshot.recovery` exposes health fraction, low/critical/regenerating
flags, time since damage, suppression, effect, pulse, hit flash and heartbeat
frequency. `player:health` and `player:heartbeat` notifications provide the
state for later HUD/audio work. Heartbeat sound remains step 15. `explosion`
notifications accept `{position, radius, token?}` for feedback; the grenade
owner in step 12 will apply obstruction-aware damage separately.

All **257 Lua checks in 28 suites** passed, plus 12 baseline-tool checks.
The same **13 native/browser scenarios** cover recovery, pause, Bullet falls,
real projectile near misses/hits, wall occlusion, explosions, death and restart.
Each backend also passed three healthy/low-health/recovered pixel gates, with
visually inspected captures. Native used Defold 1.14.0/Metal; browser used its
release Wasm engine in Chrome WebGL2/ANGLE Metal. These establish implementation
behavior, not controlled reference visuals, audio or sustained performance.

```sh
lua tests/health_test.lua
PYTHONPATH=automation-bridge-python python3 tests/health_smoke.py
# Build a release wasm-web bundle with tests/health_browser.project, then:
PLAYWRIGHT_MODULE=/path/to/playwright node tools/validate_health_browser.mjs --bundle=/path/to/bundle
PNGJS_MODULE=/path/to/pngjs node tests/health_pixels.mjs build/health-native-validation
PNGJS_MODULE=/path/to/pngjs node tests/health_pixels.mjs build/health-browser-validation
```

Reports and screenshots are under `build/health-native-validation` and
`build/health-browser-validation`; standalone logs are under
`build/health-unit-validation`. Browser bundling used the editor's Bob endpoint
with `platform=wasm-web`, `architectures=wasm-web`, `variant=release`, `archive=true`,
`settings=[tests/health_browser.project]`, and a separate `output` directory.

## Faster material-atlas loading (2026-10-17)

Atlas baking now fills an **896-command budget** per loading update instead of
limiting copies/filters to eight jobs and giving every recipe its own frame.
The remaining 128 commands are reserved for the loading screen and HUD. The
first scene render runs in the following update, after the final bake commands
have consumed their scratch textures; renderer readiness is reported then.

At medium quality this reduces baking from **194 to 31 updates**. Three fresh
macOS/Metal debug captures reduced median combined readiness from **1.706 to
0.825 seconds (52%)**, measured from world initialization. Renderer readiness
fell to **0.345 seconds**, with world generation now finishing last. Both sets
use the same native mesh/audio engine, 1920×1280 drawable and unchanged VSync.
These are application wall times, not GPU timestamps. Baseline evidence comes
from the preceding startup profile with matching sources and engine binary.

The recipe/filter order, 1,145 jobs, reported 1,727 bake draws, atlas dimensions
and preservation passes are unchanged. All three medium-quality atlas RGB maps
match the original pixel-for-pixel, including their mip regions. Command-count
tests cover all material qualities and context rebakes: 28/31/35 updates for
low/medium/high, with at most 914 commands including the loading UI.
`renderer.snapshot` exposes `bake_frames`, `bake_peak_commands` (bake work only)
and `bake_command_budget`. See the local
[measurements and validation](captures/bake-scheduling-2026-10-17/findings.txt).

## Native procedural audio (2026-10-17)

The [AudioSynth extension](audiosynth/README.md) now generates the 76-sound bank
in C++: waveform math, seeded noise, filters/echoes, fades, statistics and PCM16
packing. Lua keeps the existing sound definitions, mixer and Defold resource
ownership. Native synthesis is the default; `audio_synthesis.backend=lua` selects
the reference, and `audio_synthesis.verify=1` compares every generated WAV.
Rebuild the custom engine after changing C++.

Three alternating fresh Lua/native pairs on macOS/Metal reduced median audio
loading work from **375 to 25 ms (93%)** and bank readiness from **1,521 to 178 ms**
after world initialization. Full readiness stayed around **1.7 seconds**, with
renderer baking finishing last. Both backends use 1,024-sample chunks and the same
soft 2 ms deadline; the native safety cap is raised to 131,072 samples per update
so the old eight-chunk limit no longer forces at least 107 updates.

Three matched Chrome 155/Wasm pairs reduced median audio loading work from
**1,005 to 45 ms (96%)**, bank readiness from **6,351 to 397 ms**, and full
world/audio + renderer readiness from **6.37 to 3.29 seconds (48%)**. Measurements
use debug Defold 1.14.0, medium materials and unchanged VSync; macOS uses a
1920×1280 drawable, HTML5 a 960×598 canvas. Verification is off in timing runs;
optional full-WAV fingerprinting is on for both backends. Comparisons are within
each platform, and readiness excludes engine/browser launch time.

All 76 WAVs match Lua byte-for-byte on macOS and Wasm, including frame counts and
durations; peak/RMS metadata matches within 1e-12. Tests also cover changed seeds,
chunk sizes, single-sample sounds, invalid inputs, returned-string ownership and
cancellation. See [configuration and repeatable validation](audiosynth/README.md).
Local evidence: [findings](captures/native-audio-2026-10-17/findings.txt) and
[per-run measurements](captures/native-audio-2026-10-17/comparison.json).

## Native world meshes (2026-10-17)

Loading steps 5 and 6 now use the in-repository [WorldMesh extension](worldmesh/README.md):
C++ builds and batches triangles and fills Defold buffers. Lua retains recipes,
face clipping, metadata and mesh resource/component installation. The native
backend is the default; `--config=world_mesh.backend=lua` selects the original
implementation, and `--config=world_mesh.verify=1` checks every native shape
against it. Rebuild the custom engine after changing C++.

Three alternating Lua/native fresh-process pairs on an Apple M3 Pro produced
these median elapsed times, with the existing 4 ms loading budget:

| Stage | macOS Lua → native | HTML5 Lua → native |
| --- | ---: | ---: |
| 5: Construct and batch meshes | 806 → 135 ms | 3,285 → 267 ms |
| 6: Fill/install buffers | 877 → 32 ms | 1,178 → 43 ms |
| Steps 5–6 combined | 1,635 → 166 ms (90% less) | 4,459 → 309 ms (93% less) |
| World/audio and renderer ready | 2,165 → 1,745 ms (19% less) | 5,573 → 3,401 ms (39% less) |

Times start at world initialization and exclude engine/browser startup. Each
row is the median of its own per-run measurement. These are frame-spanning
intervals, including scheduling and concurrent loading work. On macOS, the
corresponding CPU scope medians fell from 372 to 54 ms for mesh construction
and from 323 to 13 ms for upload. Audio synthesis and renderer baking now
limit the overall improvement. Verification is disabled in timing runs.

Both platforms used Defold 1.14.0 debug engines and medium materials; native
Metal used a 1920×1280 drawable, while Chromium 149/WebGL 2 used a 960×598
canvas. Comparisons are within each platform with identical settings. HTML5
uses a test fixture that unpauses the game and freezes AI.

All 4,532 shapes matched their Lua references, including float32 bits and bounds,
on **both macOS and Wasm**. All **513 installed stream hashes across 86 batches**
and all batch bounds matched the Lua backend in every run. The level remains
413,568 vertices and 1,224 colliders. Native primitive, glass, ownership and
cancellation checks passed on both platforms. Each also passed real Bullet
checks for 196 nodes/201 edges, 108 actor route queries and eight inspection
captures. The 45 affected standalone Lua checks passed.

See [extension usage and repeatable tests](worldmesh/README.md), the local
[measurement report](captures/native-worldmesh-2026-10-17/findings.txt), and
[per-run comparison data](captures/native-worldmesh-2026-10-17/comparison.json).

## Level-loading optimization (2026-10-16)

Native Defold 1.14.0/Metal Remotery measurements at 1920×1280, medium materials,
with VSync unchanged, improved from **7.51–8.79 seconds to 2.06–2.19 seconds**
across three fresh processes per version. Median recorded loading fell from
**8.56 to 2.07 seconds (76%)**.

| Measurement | Before median | After median | Reduction |
| --- | ---: | ---: | ---: |
| World loading interval | 8,560 ms | 2,074 ms | 76% |
| Geometry work | 882 ms | 536 ms | 39% |
| Mesh construction | 594 ms | 326 ms | 45% |
| Box construction | 434 ms | 217 ms | 50% |
| Face-neighbour lookup | 89 ms | 38 ms | 57% |
| Lua-to-buffer copies | 342 ms | 308 ms | 10% |
| Largest mesh-upload update | 12.17 ms | 4.36 ms | 64% |
| Collision installation interval | 2,213 ms | 127 ms | 94% |

Loading now fills a 4 ms work budget, with guards of 4,096 geometry jobs or 128
upload slices/colliders per update. Buffer copies yield every 512 vertices;
meshes become visible only after their complete buffers are installed. Batch
boundaries and order are unchanged. Shape transforms and invariant box attributes
are calculated once, face neighbours use an 8-metre spatial grid in original
recipe order, and sorted edge lookups skip irrelevant prefixes.

The level remains **4,532 shapes, 86 batches, 413,568 vertices and 1,224 colliders**.
A complete canonical generated-world export matches exactly, including navigation,
collision, lighting and every mesh value. All **513 native buffer stream hashes**
and batch bounds match the original. Material quality, render settings, atlas sizes,
render-target allocations and bake jobs/draws also match. No shaders, materials,
layout, recipes or tessellation were reduced.

Validation passed 23 world, 8 face/edge and 4 upload tests, plus native support for
all 196 navigation nodes, bidirectional capsule checks on all 201 edges, and 108
actor route queries. Fourteen rendered views were compared: six are exact, and
13 fit the maximum variation measured between three original-rendering launches.
One daylight-sky capture differs at 14 of 921,600 pixels versus a nine-pixel control
maximum (the same maximum channel error of 24); the strict image gate remains
failed for that view, with raw evidence retained. Native geometry bytes and renderer
settings are identical. This sparse capture variation is not used to weaken tests.

The timing interval starts at the first captured world update and ends at readiness;
startup and the first recipe frames are excluded. All mesh/clipping/upload/collision
work is captured. These are CPU-thread elapsed scopes, not GPU timestamps; one
original run includes a 1.01-second uninstrumented engine stall. Nested scopes in
the table must not be added together. The remaining buffer-copy work is spread
across more frames to avoid its old 10–16 ms upload spikes.

Compile in the editor, then run
`PYTHONPATH=automation-bridge-python python3 tests/loading_profile.py --output captures/loading-profile/new-run`.
The harness owns its native engine and saves raw samples, phase spans, counters,
source hashes and coverage. `--uncapped` is an optional VSync diagnostic.
`lua tests/world_fingerprint.lua output.bin` exports canonical generated data;
`world.mesh_fingerprints` pages native stream hashes for engine-side verification.
See the local [optimization report](captures/loading-optimization-2026-10-16/findings.txt),
[comparison data](captures/loading-optimization-2026-10-16/comparison.json), and
[original investigation](captures/loading-profile-2026-10-16/findings.txt).

## Profiling and CPU optimization (2026-10-16)

The projectile query's starting-inside fallback now cheaply rejects unrelated
colliders before its full box intersection. Soldiers reuse separate simulation
pose storage, and the HUD/minimap updates only changed properties. These changes
preserve collision intervals, animation cadence, all geometry and render settings.

Matched Defold profiler captures on an Apple M3 Pro (native debug Metal) collected
8,103 baseline and 8,159 optimized complete `Main/Step` samples across eleven
scenarios per version. Scope costs below are milliseconds per rendered frame;
spawn figures combine two 600-frame runs.

| Measurement | Before | After | Reduction |
| --- | ---: | ---: | ---: |
| Projectile update, 720p firing | 0.827 ms | 0.104 ms | 87% |
| Simulation skeleton pose, 720p spawn | 0.204 ms | 0.039 ms | 81% |
| HUD update, 720p spawn | 0.294 ms | 0.159 ms | 46% |
| Whole-frame p95, 720p firing | 10.397 ms | 9.101 ms | 12% |

720p spawn/sprint remain near the 8.33 ms pacing floor. Retina 1920×1280 did
**not** improve: paired mean frame time rose from 13.577 to 13.927 ms, with p95
around 29.4–29.7 ms. The resolution-dependent rendering/presentation bottleneck
remains; these elapsed scopes are not GPU timings. Both firing runs produced
identical weapon results, including 61 shots, 63 impacts and one exit.

Validation passed 96 affected Lua checks and native weapon, AI and HUD suites.
Seven of fourteen image comparisons are exact; all fourteen fit an unchanged-code
cross-launch control in changed-pixel count, peak error and mean error. The worst
optimized view differs on 34 of 921,600 pixels, versus 46 in the control. Exact
cross-launch assertions therefore failed in both builds; the full measurements
are retained rather than hidden by an arbitrary tolerance. Renderer settings,
world counts, target allocations and frozen draw counts match.

`tests/performance_profile.py --output captures/performance/before` records the
baseline; add `--compare captures/performance/before` with a new output directory
for the optimized round. Run with `PYTHONPATH=automation-bridge-python:tests` and
Pillow installed. `--visuals-only` isolates image captures; `--noise-control`
optionally names a measured unchanged-code repeat. `tests/hud_update_smoke.py`
checks minimap pool reuse, floor/heading/resize changes and combat HUD updates.
The local [comparison report](captures/performance-optimization-2026-10-16/findings.txt)
details the retained raw captures and validation evidence.

## Parity step 4: architecture, interiors and dressing

The world now builds W1/W2/W4/W5 setbacks and terraces, balconies with rails and
brackets, recessed upper windows, arched trim, chamfered caps, roof tanks, huts,
sheets, dishes and aerials. W3 and E3 have broken upper walls, surviving slab
strips, exposed beams and rebar; E3's ground floor remains connected without
inventing stairs. The gate has a pointed opening with wedge stones, four stepped
masses, cornices, corbels, loggia details, merlons and rampart sandbags.

W2 has the source shop/storage/living programme and a 2.4 m upper setback. Its
hall opening and upstairs furniture are adjusted around the validated stairs;
a second opening preserves the reference interior sightline. E1 adds its shop
and storage divisions, stocked shelves and wall/ceiling furnishings. E3 gains
ruin/storage furnishings and fallen material. E2 retains the existing adapted
three-floor interior. Seven new navigation nodes reach the added room areas.

Eight open-legged stalls, eight additional barriers, four sandbag emplacements,
three wrecks, seven palms, five lamps, six cable spans, six laundry lines, four
tyre stacks, rugs, rubble and small props complete the authored families.
Several placements move slightly to keep the street and flank routes clear.
Heavy objects use simple collision envelopes and explicit cover positions;
small scatter has independent, named random streams and never changes physics,
spawns or weapons. Rounded/rotated/cutout geometry cannot subtract rectangular
holes from nearby walls. Opaque surfaces share spatial batches using per-vertex
material IDs and weather amounts; fully hidden shapes contribute no mesh data.

The final map has **4,450 shapes, 85 batches, 1,224 colliders, 409,386 vertices and
32,750,736 vertex-stream bytes (31.23 MiB)**. Geometry and collision counts are
unchanged by batching. The extra two floats per opaque vertex cost 3.12 MiB;
glass retains its original stream and separate sorted draws. Architecture uses
16-metre cells and sparse terrain uses 64-metre cells, with a hard 12,288-vertex
limit per buffer. Loading now uses the 4 ms budget and sliced uploads described
in the loading-optimization section above.
Individual jobs may exceed the deadline, and `world.snapshot` reports the peak.
These are allocation/submission counts, not measured GPU or process residency.
The measured native load accumulated 1,482.486 ms of work with a 15.823 ms largest
update. The material atlas remains 76.92 MiB at medium quality; no render targets
were added.

World, depth and shadow draws now request all six frustum planes. Defold's
[default side-plane culling](https://defold.com/ref/render/#render.draw_options)
omits near/far planes, which previously submitted distant geometry to local
shadow maps. Combined with spatial batching, native 1280 × 720 measurements are:

| Frozen view | Before draw calls | After draw calls |
| --- | ---: | ---: |
| Street | 3,379 | 535 |
| Interior | 3,264 | 498 |
| Courtyard | 2,762 | 423 |
| Facade detail | 2,370 | 363 |

The live spawn view with AI, weapon, HUD and temporal AA submitted 578 calls
across 64 delivered profiler samples. The frozen views delivered 15–16 samples
per 60-frame request. These are short submission measurements, not sustained
combat frame-time or GPU benchmarks. All visual features remain enabled.

Batching validation passed 72 Lua checks, the native shadow coverage/camera/resize
suite, 108 native route queries, four repeatable native stills, and all 62 WebGL
catalogue stages with material, foliage, depth, shadow and motion pixel checks.

`tests/world_detail_capture.py` captures the matched street/interior/courtyard
views plus facade detail, checks exact repeats, and requests 60 frames of CPU scopes
and render counters. It enforces fewer than 650 calls in these frozen views and
fewer than 800 in a subsequent live spawn sample (delivered sample counts are
retained in the manifest). The corresponding Three.js adapter selection is
`--shots=street,interior,courtyard`. Source-derived content and route validation
are implemented; reduced geometry, partition/prop placement adaptations and
remaining lighting/exposure differences are explicit. The final cross-engine
visual and sustained 60 FPS gates remain in steps 18–19.

Validation passed 185 Lua checks, 12 baseline-tool checks, the native full
player/AI traversal matrix, final native/WebGL capsule checks and 108 route
queries per backend, eight browser minimap pixel gates, and four exact native
still repeats. The full player walk preceded the last stall/frond refinements;
the final stall collision passed fresh capsule checks on both backends.
The current source lock includes the four native and three Three.js still
receipts; other camera scenarios remain unqualified for this increment.

## Parity step 3: complete surface catalogue

The runtime catalogue now contains nineteen surface families plus the shared
microdetail recipe. Sand, corrugated metal, burlap and foliage keep IDs 16–19;
ID 15 remains microdetail so existing world and weapon materials retain their
mappings. Sand uses the reference 2.5 m ripple tile, corrugated sheets use a
2.4 m tile with twelve ridges, and hessian uses the world palette's 0.16 m tile
and tint. Hessian's normal bake retains the reference 0.5 m bake scale; using
the visible UV scale for that bake incorrectly triples its slopes. Foliage
uses a 0.6 m tile of overlapping, varied leaves. All maps, wear, roughness and
relief are generated during bounded loading.

At the surface-catalogue increment, outer terrain gained sand, including its
collision/audio surface name. That version used 374 batches,
1,983 boxes, 543 colliders and 148,596 vertices / 10,698,912 mesh bytes. Its 189
navigation nodes and 194 edges are unchanged. The mesh pool is 640 to accommodate
the full map, six soldiers, weapons, effects and the expanded optional laboratory.
The subsequent step-4 resource account below supersedes these historical map counts.

Foliage cards have both windings and a negative vertex-alpha coverage tag.
Colour, camera depth/motion, sun shadows and point-light shadows sample the same
padded mask mip chain. The 0.45 near cutoff transitions to a fixed ordered mask
when leaves become subpixel, preserving distant coverage for TAA instead of
turning the card opaque or losing all leaves. The mask lives in albedo alpha;
leaf vein/curvature height is kept separately in material alpha for normal
baking. Foliage does not use parallax. The world pass reuses its existing atlas
sampler/uniforms to stay within Defold 1.14's 32 resource bindings per set;
depth/shadow overrides receive their own eleven mask rectangles. `view=coverage`
shows atlas alpha for pixel inspection. Shadows still have their own filtering
and texel footprint; this is not per-pixel equality across render passes.

| Material tier | Atlas dimensions | Mip regions | Bake jobs / draws | Three resident maps |
| --- | --- | --- | --- | --- |
| Low | 1024 × 1650 | 174 | 1025 / 1547 | 19.34 MiB |
| Medium | 2048 × 3282 | 194 | 1145 / 1727 | 76.92 MiB |
| High | 4096 × 6546 | 214 | 1265 / 1907 | 306.84 MiB |

These are atlas allocations, not total process or GPU memory. Temporary bake
storage and the render pipeline are accounted separately by `renderer.snapshot`.
Sustained performance remains steps 18–19.

Capture catalogue v13 has 71 cameras, including fifteen new close, distant,
grazing, back-face and shadow views. The new test entry points are:

```sh
# After a current native editor build; owns one process per quality tier:
PYTHONPATH=automation-bridge-python python3 tests/catalogue_smoke.py --motion
# Build debug wasm-web with --settings tests/catalogue_browser.project,
# then use the existing browser capture harness (62 stages at medium quality):
node tools/validate_rendering_browser.mjs --bundle=/path/to/bundle --output=build/material-catalogue-browser-validation
PYTHONPATH=automation-bridge-python python3 tests/catalogue_browser_pixels.py
```

The 2026-10-15 validation passed 183 Lua checks, twelve baseline-tool checks,
all three native material tiers, 45 exact still repeats, four 121-frame medium-tier
sweeps without history resets, and all 62 medium-tier WebGL stages and pixel gates.
A fresh native full-map quick run also passed all 543 collider dimensions, 189
supported nodes, 194 links in both directions and 78 six-actor route queries.
All owned engines closed without runtime errors. Full player traversal circuits
and sustained performance were not rerun for this material increment.

The native checks inspect every mip border/channel, leaf-mask energy, exact
camera returns, front/back coverage, depth, sun/local shadows and optional four
121-frame motion sweeps. The browser pixel checks inspect the same medium-tier
maps and fixtures, motion output and exact camera/shadow returns. Captures and
reports are under `build/material-catalogue-validation` and
`build/material-catalogue-browser-validation`. These material checks do not
qualify cross-engine visual parity. The six new Three.js foliage views remain
explicitly pending until reference UV/coverage and shadow fixtures are matched.

## Run and validate

Open `game.project` in Defold 1.14.0, fetch libraries, then build and run.
The existing Automation Bridge dependency supports native smoke checks.

### Mobile touch controls

Android and iOS show touch controls automatically. HTML5 also enables them on
touch-capable browsers, or when the first multi-touch event arrives. Desktop
keyboard/mouse controls remain available. The overlay is designed for landscape
play, adapts to window size, and keeps its controls inside the platform safe area.

- Drag the left stick to walk; push fully forward to sprint. Back off and push
  forward again quickly for tactical sprint.
- Drag the **LOOK** pad to turn. Hold **FIRE** to shoot; dragging that finger also
  looks, so two thumbs can move, aim and fire together.
- Tap **AIM**, **CROUCH**, or **PRONE** to toggle. Crouching during a sprint slides.
  Hold **JUMP** while moving into a reachable ledge to mantle.
- Tap **RELOAD**, **WEAPON**, **MODE**, or **INSPECT**; hold either **LEAN** button.
- **MENU** opens touch-accessible settings, resume and restart, including after
  death. Look sensitivity is shared with the mouse setting.

Gestures must start inside a visible control. Touches starting elsewhere stay
ignored until released, even if they move across a control. A drag that starts
on a control keeps working when the finger leaves its bounds.
Pause, focus loss, death, inspection and resizing clear touch holds and toggles;
lift and touch again to start a fresh gesture. Touch-generated mouse events are
ignored to avoid duplicate clicks, accidental shots or pointer-lock requests.
The implementation uses Defold's separate
[multi-touch binding](https://defold.com/manuals/input-mouse-and-touch/).

For a desktop layout preview, launch with `--config=touch_controls.enabled=1`;
`--config=touch_controls.enabled=0` disables touch controls, and the default `-1`
detects them automatically. Run `lua tests/touch_test.lua` for gesture/input
regressions and `PYTHONPATH=automation-bridge-python python3 tests/touch_smoke.py`
for native GUI/gameplay checks. The latter uses an opt-in action fixture because
macOS cannot inject touch hardware, and saves phone/tablet captures in
`build/touch-validation`. Physical Android/iOS device validation is still needed.

HTML5 uses a matrix constant for lens sky reprojection. On OpenGL, resizing
recreates the scene, weapon and depth/motion targets: Defold 1.14 checks
framebuffer completeness while resizing individual attachments, when WebGL can
see mismatched dimensions and abort. Other targets retain their normal resize
path; generated maps do not rebake.

Controller profiling is optional: release engines omit the `profiler` API.
Unguarded calls abort startup before world generation, leaving the loading text
visible with no console error because release logging is disabled.

For a short HTML5 regression run, bundle **release** with `--settings tests/html5_browser.project`
and run the command below. It checks street, sky and ADS views, then changes
window size three times. The fixture reports through the HTML5 console even in
release and verifies world/audio readiness and gameplay ticks. `--release=1`
rejects a debug engine, which would hide missing-profiler regressions.
WebGL errors fail both browser validation harnesses.

```sh
node tools/validate_rendering_browser.mjs --bundle=/path/to/bundle --resize=1 --release=1
```

Run the engine-independent regression suite from the repository root:

```sh
lua tests/runtime_test.lua
lua tests/world_test.lua
lua tests/movement_test.lua
lua tests/vault_test.lua
lua tests/camera_test.lua
lua tests/health_test.lua
lua tests/weapons_test.lua
lua tests/viewmodel_test.lua
lua tests/ai_test.lua
lua tests/navigation_test.lua
lua tests/squads_test.lua
lua tests/suppression_test.lua
lua tests/renderer_test.lua
lua tests/atmosphere_test.lua
lua tests/shadows_test.lua
lua tests/temporal_test.lua
lua tests/local_lights_test.lua
lua tests/combat_fx_test.lua
lua tests/photographic_test.lua
lua tests/surface_atlas_test.lua
lua tests/visible_faces_test.lua
lua tests/weathering_test.lua
lua tests/render_capture_test.lua
lua tests/audio_test.lua
lua tests/ui_test.lua
lua tests/touch_test.lua
```

With the project open in Defold, the native smoke test builds the game, checks
world loading, collision dimensions, doorway clearance, navigation, inspection
views, timing, input, damage and HUD updates, then closes the engine it launched:

```sh
PYTHONPATH=automation-bridge-python python3 tests/smoke.py
PYTHONPATH=automation-bridge-python python3 tests/building_smoke.py
PYTHONPATH=automation-bridge-python python3 tests/market_smoke.py
PYTHONPATH=automation-bridge-python python3 tests/full_market_smoke.py
PYTHONPATH=automation-bridge-python python3 tests/movement_smoke.py
PYTHONPATH=automation-bridge-python python3 tests/movement_features_smoke.py
PYTHONPATH=automation-bridge-python python3 tests/weapons_smoke.py
PYTHONPATH=automation-bridge-python python3 tests/ai_smoke.py
PYTHONPATH=automation-bridge-python python3 tests/squads_smoke.py
PYTHONPATH=automation-bridge-python python3 tests/suppression_smoke.py
# Requires Pillow for GPU pixel assertions:
PYTHONPATH=automation-bridge-python python3 tests/renderer_smoke.py
PYTHONPATH=automation-bridge-python python3 tests/atmosphere_smoke.py
PYTHONPATH=automation-bridge-python python3 tests/combat_rendering_smoke.py
PYTHONPATH=automation-bridge-python python3 tests/photographic_smoke.py
PYTHONPATH=automation-bridge-python python3 tests/photographic_adaptation_smoke.py
PYTHONPATH=automation-bridge-python python3 tests/shadows_smoke.py
PYTHONPATH=automation-bridge-python python3 tests/occlusion_smoke.py
PYTHONPATH=automation-bridge-python python3 tests/temporal_smoke.py
PYTHONPATH=automation-bridge-python python3 tests/audio_smoke.py
PYTHONPATH=automation-bridge-python python3 tests/ui_smoke.py
```

The game starts in first person. **W/A/S/D** moves, **Shift** sprints, **Space**
jumps, **Ctrl** holds crouch, and **Z** holds prone. Click to capture the mouse
for looking; **Esc** opens the pause/settings menu and releases it.
Holding right mouse aims down the weapon sight
and reduces movement speed.

Double-tap **Shift** within 0.32 seconds and hold it while moving forward for
tactical sprint (8.38 m/s, at most six seconds, then 1.6 seconds recovery).
Press **Ctrl** during a fast sprint to slide. A slide continues after Ctrl is
released, lasts at most 0.9 seconds, and permits limited steering. Press Ctrl
again to cancel, Space to jump out, or Z to go prone. A 0.55-second cooldown
and a jump-exit speed cap prevent repeated bursts from adding unlimited speed.

Hold forward and press/hold **Space** near a ledge to mantle. The controller
needs a reachable face, a walkable top and room for the entire climb. It can
finish crouched when standing clearance is unavailable. **Q/E** holds a left/
right lean; release to centre. Lean is disabled during sprinting, slides,
mantles, airborne movement and prone movement. Walls shorten the camera offset.

Press **1**, **2** or **3** to inspect the street, shopfront or room, and **0** to
return to the player. Inspection disables movement input. **4** creates the
optional traversal course and puts the player at its stairs. Course lanes from
west to east contain a thin wall/corner, stairs, a high obstacle, 30°/60° ramps,
a low ceiling and narrow/wide doorways. The course is separate from the street.
Its second row, farther ahead at z=-15, adds 1.2/1.8-metre ledges, an unreachable
wall, blocked/crouch-only headroom, a narrow top and an obstructed climb approach.

**Left mouse** fires, **R** reloads, and **F** inspects. **6/7/8** selects the
rifle/SMG/pistol; **Tab** cycles weapons, and **B** cycles the equipped weapon's
fire mode. The first click captures the mouse; subsequent clicks fire. **5**
creates an optional firing range and moves you to its bare-target lane.
The other lanes, to the right, have thin wood and thick concrete in front of
their targets. Targets have 1,000 health and use the normal damage owner.
Gamepad/touch adapters can feed the same `game.input` API later.

## HUD and pause menu

The HUD includes a spread-reactive crosshair, hitmarker (mint for a headshot),
health bar, low-health edge tint, a brief damage flash and a directional hit
indicator when the attacker is known. It shows the current weapon, fire mode,
ammunition, reload/inspection status and movement stance. Elimination displays
a restart prompt. A top-right FPS counter averages frame rate over half a second
and continues updating while paused. A four-entry killfeed records confirmed
deaths through combat notifications, expires after six active seconds and clears
on encounter restart.

The compass uses north = world -Z and east = +X. The north-up minimap follows the
player over a 44-metre square, drawing the generated world's collision footprints
and a rotated player marker. Rectangles are clipped to the map and the player's
floor height, so the shop's roof does not fill its accessible interior. The
current slice supplies 190 rectangles; the GUI bounds this to 256 for larger maps.
It shows geometry, not enemy positions. Renderer diagnostic views hide the combat
HUD while leaving the settings menu available.

**Esc** toggles the menu. Use the mouse to select tabs, click/drag sliders and
toggle options, or **Tab / Up / Down** to select a control, **Left / Right** to
adjust it and **Enter** to activate it. The menu provides:

- **Audio:** master, weapons, movement/impacts and ambience volumes, plus mute.
- **Display:** sun shadows, surface detail, local lights, fog, bloom, exposure
  and the renderer's diagnostic views.
- **Controls:** mouse sensitivity (0.25–3× the existing tuning) and control help.
- **Resume** and **Restart encounter**, also usable after player death.

Settings apply immediately and survive encounter restarts; they are session
settings and reset to defaults when the application is relaunched. Existing
`audio.configure` and `renderer.configure` commands update the same live values.

Pause freezes the gameplay clock, player/AI movement, rounds, reload/weapon
timelines and HUD feedback timers. Queued damage waits until the next resumed
fixed tick. Loading, rendering, GUI input and sound completion callbacks remain
live; the mixer stops voices and drops stale cues. Focus loss pauses and releases
the cursor. Returning focus leaves the game paused until explicitly resumed.
Resume clears buffered input and quarantines held gameplay buttons until release.
The cursor stays free: the next click captures it without firing, and a subsequent
click fires. This also avoids requiring browser pointer lock from a menu message.

HUD clusters anchor to screen edges and scale together; the menu fits inside the
window while preserving its aspect ratio. The GUI uses only generated box/text
nodes, capped at 384, with no new texture assets. Menu tabs delete their old nodes
before rebuilding. Minimap metadata is sent once in bounded messages, and HUD
presentation remains separate from simulation.

`tests/ui_test.lua` covers pause timing, in-flight rounds and pending damage,
loading while paused, focus transitions, input quarantine, compass/damage
direction and minimap clipping. `tests/ui_smoke.py` exercises actual GUI controls,
native AI/audio pause, held inputs, reload resume, cursor capture, killfeed,
restart and window resizing, saving review images in `build/ui-validation`.
Physical mobile and browser UI/input validation remain separate work; this
increment does not add gamepad or touch adapters.

Two squads of three patrol the street and west courtyard/rear lane. Approach a
patrol to trigger detection, shared squad alerts and combat. **9** restarts the
encounter with full player/enemy health, fresh weapons and ammunition.
Inspection cameras pause enemy simulation. The separate world/movement/weapon
smoke suites explicitly pause AI to isolate their fixtures.

## Procedural soldier and combat

`game/ai/rig.lua` retains the reference's 25 joint names, hierarchy and metre
proportions, rotating the source's +Z-facing carry pose into this project's -Z
convention. The bind axes are identity rotations; they do not yet reproduce the
reference ragdoll joint frames. `geometry.lua` generates cloth limbs, helmet,
goggles, carrier, pouches, boots, gloves and a simplified carried rifle. The
mesh has 7,140 vertices and 514,080 bytes of float streams: position, normal,
colour, four joint indices and four normalized skin weights. Some vertices blend
two joints; rigid equipment follows one. No model or animation is imported.

`soldiers/soldier.vp` performs linear blend skinning with 25 matrix uniforms.
Each palette is 1,600 bytes. Colour and temporal prepasses receive three palettes
(current colour, current prepass and previous prepass), totalling 4,800 bytes.
Three array assignments plus one previous-root matrix use four `go.set` calls
per actor per presentation frame. Two reusable matrix palettes preserve the
previous rendered pose for motion vectors. Presentation also owns reusable Lua
pose buffers, separate from authoritative simulation poses and other soldiers.
The identity bind axes allow inverse-bind composition to update only translation.
One shared generated buffer serves all six soldiers and
replacement instances; each live soldier uses two mesh components on one GO, one movement capsule and
eleven hit-volume GOs. Conservative bounds include the supported animations and
death collapse. The fragment shader supplies procedural camouflage, with the
world's sun, ambient light and fog. `skinning.glsl` is shared by the colour and
animated sun shadow passes introduced in renderer step 6.

A native Defold 1.14.0 arm64-macOS comparison with six active soldiers and a
stationary player used 60 warmup frames and 600 recorded frames per version.
Soldier presentation fell from 0.876 to 0.441 ms average (0.642 to 0.406 ms median;
2.657 to 0.799 ms P95). Total controller `late_update` fell from 0.959 to 0.533 ms
average. The `soldiers.pose` and `soldiers.upload` profiler scopes separate pose
evaluation from shader uploads. These are debug CPU measurements with no shots
fired, not GPU timings or a sustained combat benchmark.

Idle breathing, distance-driven walking, upper-body aiming, recoil and a bounded
0.85-second death collapse are evaluated in Lua. Simulation poses advance at 120
Hz. Presentation interpolates position, heading and pose parameters without
changing collision transforms. This is a deliberately simplified animation
prototype: terrain-following foot/hand IK, source clip parity and physics ragdolls remain
later work. Death disables hit volumes and leaves one visible corpse until
restart.

`game/systems/ai.lua` owns six ordered actors and a shared bounded enemy
projectile pool (128 live rounds). The layout supplies stable
`enemy_1`–`enemy_6` IDs, squad membership, supported spawn positions and
individual patrol endpoints. A patrol detects a visible player within 14 metres
and a 130-degree field of view, after four perception checks at roughly 10 Hz.
An alerted squad remembers an observed position for eight seconds and can see up
to 24 metres. Visual acquisition or player damage shares the point with living
squad members. Receiving a report does not renew or rebroadcast it; lost contact
expires even behind walls. Single-soldier test fixtures retain their five-second
memory. Each actor pursues until within ten metres with a clear muzzle path,
then aims and fires one 400 m/s round every 0.55 seconds. A round starts at the
animated rifle muzzle, uses existing travel/drop/penetration code and queries
the actual player capsule. Health still changes only through `game/combat.lua`,
on the following fixed tick. Each actor has its own seeded random stream.
Friendly firing lanes are checked before shooting; enemy projectiles damage the
player and do not damage allies. Dead players cannot be reacquired or fired on.

Patrol/pursuit routes use shortest paths over the existing authored, layered
navigation graph, including temporary start/goal links. Native queries validate
floor support and capsule clearance before accepting a connection. Movement then
uses the same swept capsule controller as the player, including kerb step-up,
wall sliding and overlap recovery. Perception checks are staggered across
actors. Routes refresh when goals move, a route fails, or movement stalls;
static-world graph edges are checked lazily and cached for the encounter.
Endpoint searches use a spatial grid: at most 12 nearby candidates within 12 m,
retaining up to four clear links. A failed local route expands to at most 24
candidates within 24 m and 12 clear links, supporting the sparse alley spans.
Floor and stair-entry restrictions apply before probing. Up to 64 exact endpoint
positions retain their validated connections; moving endpoints get fresh checks.
Replacing the navigation graph or restarting clears these caches.

`game/ai/planner.lua` schedules each actor's decisions and clearance probes round
robin, sharing a 2 ms / 32-resumption budget across all fixed ticks in a rendered
frame. This is a soft CPU limit: an individual probe finishes before yielding.
Cover searches use the same queue and recheck exclusive ownership on completion.
Soldiers keep following their existing routes while replanning; before installing
a delayed result, its first link is checked against the soldier's current position.
Death, replacement, inspection and explicit patrol changes cancel stale jobs;
pause preserves them without advancing. `ai.navigation`, `nav.direct`,
`nav.endpoints`, `nav.static_edges` and `nav.reconnect` expose the work in the
native profiler. Unreachable paths retry at most once per second.
`PYTHONPATH=automation-bridge-python python3 tests/navigation_profile.py` rebuilds,
runs the original six-second forward sprint plus two-second idle, and records
spawn/forward captures under `build/forward-run-profile/optimized`. It restores
normal combat settings and leaves a fresh encounter running at spawn.

The native forward-run captures in `build/forward-run-profile/navigation-comparison.json`
measure 37.1 FPS before this change and 73.5–82.1 FPS afterward (two runs).
In the final run, stationary spawn and forward movement took 13.37 and 13.60 ms
per frame respectively. AI CPU work fell from 18.02 to 3.24 ms per rendered frame,
with navigation/decisions at 0.43 ms versus 14.92 ms previously spent on routing.
These are local debug captures; all runs use the same movement sequence and
six active soldiers. Scope totals are divided by all rendered frames, including
frames with no navigation work.

Nearby actors use local separation steering; world collision remains
capsule-swept. This is not rigid actor-to-actor blocking.

`game/ai/tactics.lua` coordinates the encounter. Cover selection requires an
unclaimed, reachable position within firing range that shields the lower body
and gives a standing firing lane. Claims are exclusive across both squads and
release on death, lost contact, invalid cover, stalled movement or restart.
At low cover, soldiers alternate a deep crouch with short standing firing windows.
Actor-index offsets stagger those windows without consuming weapon randomness.
Standing requires capsule headroom; firing additionally requires a nearly risen
pose, live visibility and clear muzzle/ally checks. While hidden, soldiers retain
valid cover and use the existing last-seen memory; crouching does not grant sight
through the barrier. With a visible ally engaging, one other squad member can claim the
generated west loop, follow its approach, rear lane and opposite exit, then
rejoin combat. One actor may claim that lane at a time. Target displacement,
lost contact and movement failure cancel the tactic; a cooldown prevents
immediate repeated circuits. The route is generated from the same layout as
navigation.

`game/ai/suppression.lua` observes actual travelled player projectile segments,
including non-tracers, within 2.2 metres of the animated head. Near misses require
world line of sight and never extend past a round's stopping point. Impacts within
2.5 metres also add pressure; impact sound through cover is attenuated to 60% and
limited to 1.5 metres. One round contributes only its strongest stimulus per actor,
so successive segments, entry/exit and overlapping volumes cannot multiply it.
Weak round-token keys expire with the projectiles. Friendly rounds are ignored;
pressure neither deals damage nor reveals the player's position.

Pressure is bounded to 1.6, decays at 0.55 per active second, triggers suppression
at 0.9 and releases it at 0.3. Suppression immediately prevents firing, cancels a
flank and forces a duck while retaining valid cover. After recovery, a short hide
interval precedes the next peek. Pause and disabled AI freeze pressure and exposure
timers; replacement clears them. The crouch palette lowers the pelvis, bends the
legs toward planted ankles and keeps the rifle above the floor. Mesh, shadows,
head-based perception, muzzle and authoritative hit volumes use the same pose;
presentation interpolates it without modifying simulation collision.

Head, chest, hips, thighs, shins and both upper arms/forearms have kinematic
Bullet boxes transformed by the same skeleton as the mesh. Projectile thickness
is measured in each box's rotated local frame. Step 8 uses reference regional
scales (4× head, 1× chest, .9× hips, .65× arms, .7× legs); overlapping volumes
submit at most one hit per actor per round. Hands and equipment have no separate
damage volumes. See the step-8 validation above for current coverage.

The 13 soldier Lua tests check mesh winding and weights, bind/deformed poses,
animated bounds, rotated hit volumes, headshot/duplicate-damage rules, routing,
perception, occlusion, death/reset and 30/60/144-FPS equivalence. Eleven
additional squad tests cover stable spawns, report expiry, exclusive claims and
death handoff, flank waypoints, ally avoidance, multi-target damage, repeated
reset cleanup and six-actor frame-rate equivalence. Native Metal validation
checks patrol, actual head/body shots, return fire, wall occlusion, shop entry,
repeated replacement, keyboard restart and clean teardown. The snapshot reports
Lua-side palette upload time and AI tick cost; these are not GPU timings or
whole-frame performance measurements. `tests/squads_smoke.py` checks six native
actors, protected cover fire, a completed rear flank during ongoing combat,
pause, all six deaths and eight full replacements. Its profiler and review
images are saved in `build/squad-validation`. That historical increment used 54
objects and 42 live hit volumes; step 8 raises those to 78 and 66. The soldiers
retain one shared 0.49 MiB mesh buffer; the existing
mesh/collision/audio limits are unchanged. A debug `wasm-web` bundle also passed
a manual WebGL 2 browser check for world/soldier rendering, walking, enemy
return fire, player death and key-9 restart, with no new console errors. That
check caught and fixed a GLSL ES reserved-word error accepted by Metal. The
browser check is narrower than the native automated suites; physical mobile
devices and full browser regression coverage remain untested.

The six-actor HTML5/WebGL 2 fixture also passes protected cover fire, a full
rear flank during 245 enemy shots, all six deaths and eight full resets, with no
runtime errors. Build a debug `wasm-web` bundle with Bob's `--settings
tests/squads_browser.project` to opt into this scenario. It prints
`SQUAD_BROWSER START/COVER/FLANK/DEATHS/PASS` records and freezes the successful
encounter for review. Normal builds omit the setting and run normal gameplay.

Nine additional Lua suppression tests cover stopped/non-tracer rounds, per-round
deduplication, impact range, friendly/dead filtering, recovery, pause, blocked
headroom, cover retention/expiry, planted feet, mesh bounds, hit volumes, reset
and 30/60/144-FPS equivalence. All 119 Lua checks pass. The shared native Metal and
HTML5/WebGL 2 fixture fires real rounds past a cover holder and into the barrier,
checks that firing stops, verifies the head volume drops from about 1.67 m to
0.77 m behind actual Bullet cover, and waits for recovery and resumed fire.
That suppression increment retained 54 objects and 42 hit volumes; step 8 adds
arm volumes, bringing the counts to 78 and 66 with the same shared mesh buffer.
Native screenshots and results are written to `build/suppression-validation`.
For the browser fixture, bundle debug `wasm-web` with Bob's
`--settings tests/suppression_browser.project`; stdout reports
`SUPPRESSION_SCENARIO PEEK/PASSES/IMPACTS/RECOVERED/PASS`.
Sideways peeks around tall cover, squad peek permissions, terrain IK and physical
mobile validation remain outside this increment.

Baseline before suppression/peeking, measured on this Mac on 2026-10-14 with
diagnostic health damage disabled while
physical bullets, impacts, sound and rendering continue:

| Measurement | Native Metal debug | HTML5/WebGL 2 debug |
|---|---:|---:|
| Mean AI fixed-tick CPU | 0.98 ms | 1.62 ms |
| Peak AI fixed-tick CPU across the scenario | 24.07 ms | 35.50 ms |
| Frame/engine-step p95 | 9.07 ms | 8.90 ms |
| Frame/engine-step p99 | 9.39 ms | 9.30 ms |

Native frame figures are the profiler's `Step` scope over a 360-frame capture;
browser figures are update intervals across 4,256 combat frames. These are
different measurements, at different viewport sizes, and do not establish a
backend speed comparison or a mobile budget. Native submitted draws averaged
157.3 (maximum 160) in the combat view. The shared soldier mesh stays at 0.49
MiB; going from one to six adds 45 game objects and 35 hit volumes. Occasional
route planning spikes remain a future optimization target. Reports are saved in
`build/squad-validation/native.json` and `browser.json`.

## Capsule movement

`game/player/capsule.lua` owns movement rules; `game/player/bullet.lua` supplies
native shape sweeps, penetration contacts and clearance tests. The player GO
has a kinematic capsule, with its origin at the feet and radius 0.32 m. Stances
resize its total height to 1.78/1.12/0.70 m. Growth requires clear headroom;
shrinking preserves the feet. Every fixed tick synchronizes the collision body
and GO to the authoritative position. Queries ignore the player itself and use
its collision filters. Defold continues to own physics stepping.

Movement waits for world loading. The controller resolves overlaps, sweeps the
whole displacement, slides along walls, accepts slopes up to 45°, steps up to
0.42 m while standing, and snaps down up to 0.34 m. A nearby walkable tread must
be verified before treating a rounded capsule/stair-edge contact as a step.
Ground probes start just above the collision skin, retaining verified tread
support across rounded edges so slow player and enemy movement cannot snap
through a stair to the floor below.
Unresolved overlaps stop integration and return to the last clear position.
Falling off the unfinished map resets position without restoring health.

`tuning.lua` keeps source-based acceleration, stance speeds, jump buffering,
coyote time and camera heights together with controller tolerances. A jump
reaches approximately 0.58 m at the 120 Hz timestep (the continuous target is
0.6 m). The camera interpolates position, mouse look and stance height, with
step smoothing. Footsteps, landings and stance/ADS state emit gameplay events;
the audio system consumes footstep, landing and stance changes for movement foley.

`moves.lua` manages tactical sprint and slide transitions. Crouch/sprint presses
are buffered edges, so render rate and a held key cannot retrigger a slide or
double-tap. Slides use drag, braking, limited steering and slope assistance;
all displacement still passes through the same swept capsule controller.
Stopping tactical sprint also starts recovery, so releasing/repressing Shift
cannot evade the time limit.

`mantle.lua` distinguishes a thin obstacle from a supported deep ledge. A forward
approach at 2.4 m/s or faster automatically vaults thin obstacles up to 0.72 m
high; speed-scaled probe intervals/lookahead catch the lip before step-up begins.
Deep ledges and taller thin obstacles require Jump, with a maximum rise of
1.85 m above the current feet. Rises within the ordinary
step allowance remain steps. Both moves require a walkable landing, capsule
clearance and a clear up/across/down path. Vaults require standing clearance on
the far side; mantles can finish crouched. The landing drop must be under 2.4 m.

Vaults last 0.34 seconds (0.493 seconds for a tall explicit vault), retain 88%
of approach speed with a 2.6 m/s minimum, and finish beyond the obstacle. Mantles
retain the existing 0.34–0.82-second climb onto the ledge. Every segment is swept
again each fixed tick, and support is checked again before completion. New
obstructions, death or inspection cancel at the last clear position. Pause
freezes progress; reset clears the move. The port deliberately keeps this swept
path instead of the references' unchecked rooted curve, and requires an explicit
Jump to climb deep ledges even when they are low.

`lean.lua` smooths a 0.34 m camera offset and 13° roll without moving the capsule.
A 0.17 m sphere sweep limits the offset, both in fixed updates and after camera
interpolation. New obstructions retract it immediately. Stance eye interpolation
is capped by the current capsule height when entering low headroom.

`camera.lua` owns fixed-tick camera state: distance/footfall-locked figure-eight
bob, landing and footstep springs, strafe/turn/air banking, breathing, slide and
mantle/vault offsets, and sprint/tactical/slide/ADS FOV transitions. Amplitudes,
frequencies, damping and transition times for locomotion come from both reference camera
implementations. Angular kicks combine a fast spring with a slow residual;
analytic integration replaces reference numerical substeps. Small deterministic
sine shake replaces the reference noise without consuming gameplay RNG. The
mantle's last pitch offset settles before releasing the move to avoid a snap.

Camera composition interpolates fixed samples and sphere-sweeps additive eye
motion after leaning, including headroom limits. Firing samples the same eye and
aim at the simulation tick; weapon recoil stays in its existing independent
channel. The world camera uses the resulting FOV, while capture/inspection
cameras and the separate viewmodel projection retain their own lenses. No new
render targets, meshes or production collision bodies are allocated.

`player.camera_impulse(ctx, kind, strength, direction)` and the `CAMERA_IMPULSE`
event accept `damage`, `suppression` or `explosion`, a nonnegative strength
clamped to 0..1, and an optional world-space direction toward the source. Existing
damage events drive the damage channel. Near-miss detection and explosion
gameplay will connect to the other channels in steps 6 and 12. The channels do
not change health. Pause/loading/death/inspection reject new impulses; pause
freezes the rig, while death, inspection and reset clear it.

Run the focused regressions with:

```sh
lua tests/movement_test.lua
lua tests/vault_test.lua
lua tests/camera_test.lua
PYTHONPATH=automation-bridge-python python3 tests/movement_features_smoke.py
PYTHONPATH=automation-bridge-python python3 tests/traversal_smoke.py
```

For WebGL, build a `wasm-web` bundle with
`--settings tests/traversal_browser.project`, then run:

```sh
node tools/validate_traversal_browser.mjs --bundle="/path/to/bundle/Claude of Duty"
```

The 2026-10-17 native Metal and Chrome WebGL2 / ANGLE Metal release runs passed
the same 13 scenarios using production
fixed ticks and Bullet: walking/sprinting vaults, explicit high vaults, thick
ledge mantles, stairs, blocked landings, pause/resume, rendered sprint/ADS FOV,
landing springs, impulse channels, dynamic obstruction and death. Reports are
written to `build/traversal-native-validation` and
`build/traversal-browser-validation`. These are implementation checks; matched
reference motion review, physical mobile devices and sustained performance
remain separate parity gates. The 244 standalone checks across 27 suites also
passed, including camera pose equivalence at 30/60/144 presentation FPS. The
existing native movement suites and full-market traversal/patrol regression
also passed: 16 player routes in both directions, 108 six-actor route queries,
E1 stair/eastern AI patrols and eight inspection captures, with clean shutdown.

## Weapons and viewmodel rendering

`game/systems/weapons.lua` owns each inventory, fire control and animation clock.
`game/weapons/defs.lua` ports the reference weapon tuning: M4A1 at 800 rpm with
auto/burst/semi modes, MPX-9 at 950 rpm with auto/semi, and P-19 at 460 rpm with
semi only. Bursts finish their three shots after trigger release and need a new
press to start again. Fractional cooldowns preserve fire rates on the 120 Hz
clock. Semi-auto requires a new press. Loading, death, inspection cameras,
sprinting and mantling suppress firing; draw/holster and reload clips also gate
shots. Firing interrupts inspection. Switching cancels any remaining burst.

Magazine and chamber are separate. The initial loads are 30+1, 32+1 and 17+1;
the HUD displays their total. Tactical reloads keep the chambered round, giving
capacity+1, while empty reloads chamber one from the new magazine. Reserve ammo
moves only at the mag-in beat (81% tactical, 71% empty); an empty reload chambers
at the 91.7% bolt-release beat. Switching before transfer leaves ammo unchanged,
and switching afterwards preserves transferred ammo. An interrupted empty
reload can finish chambering even when reserve ammo is exhausted. Holding fire
on an empty weapon does not continuously reload; a new dry trigger press starts
a reload when ammunition is available.

ADS blends the sight pose, spread and world/viewmodel FOV. Stance, movement,
airborne state and sustained fire affect spread. Seeded recoil patterns and
underdamped springs drive the camera and weapon kick separately. Input, fire,
recoil, ADS and clip events advance only on fixed ticks; camera/weapon spring
presentation interpolates between those ticks. `clips.lua` contains normalized
reload, draw, holster and inspection timelines; magazine, bolt/slide, charging
handle and hand transforms follow the same clock as ammo changes.

`ballistics.lua` advances bounded projectiles with source muzzle velocities,
linear drag, 9.81 m/s² gravity and range-based damage falloff. Every tick queries
the complete travelled segment through Bullet, capped at remaining range.
Shots start at the collision-limited eye, so a viewmodel muzzle intersecting a
wall cannot shoot through it; muzzle flash remains attached to the rendered gun.
This deliberately differs from the reference's muzzle-origin simulation.

`trace.lua` measures entry/exit thickness against the exact authored Bullet box
(including its rotation). Containing boxes are included when a ray starts inside
a solid. Material penetration costs accumulate over actual travel, including
across ticks and through overlapping solids. Damage decays with material travel;
unknown collider geometry stops the round rather than guessing an exit. The
source surface depths/energy losses are preserved; energy attenuation is
continuous here, and random penetration deflection is not implemented. Entry
and exit notifications carry surface, effect and audio routing keys. Each actor
receives at most one damage request per round, even if multiple hit volumes
intersect. The pool is limited to 128 live rounds, six penetrated layers and a
five-second lifetime. Future actor colliders can join the query registry with
`actor` and optional `headshot` metadata; the firing-range targets exercise it.

`geometry.lua` generates all three models during loading using merged primitive
recipes and source-scale attachment points. The three weapons contain 19,446
vertices across 24 independently transformable parts. Two shared, generated arm
meshes add 15,096 vertices with articulated gloves, fingers and two-bone IK.
Together their vertex streams occupy 1,442,064 bytes before resource overhead.
See the step-7 section above for motion, hand tracks and visual qualification limits.
Twenty-four pooled effect meshes provide short-lived impact particles, cases and
tracers; they have no debris physics. All generated buffers and game objects are
released on teardown. Surface audio routing now selects generated impact samples;
weapon fire and reload beats also drive the audio system described below.

`render/game.render_script` draws the viewmodel with its own camera into an RGBA
colour target with a separate depth attachment. Its lighting coordinates are
transformed through the world camera, so the same sun, shadows, environment and
room light illuminate the weapon and world. The weapon receives no world fog or
world bloom; both layers go through one exposure and tone-mapping function before
GUI. The reticle appears only in ADS. Weapon vertex alpha selects the combat
surface family while the shader writes opaque coverage. World temporal AA and
independent spatial weapon AA are implemented; arms share the latter.

The 19 weapon Lua tests cover timing, inputs, reload interruptions, deterministic
spread/recoil, geometry bounds/winding and continuous collision/penetration.
The native weapon suite uses real input bindings, fixed ticks and Bullet targets,
checks damage through wood versus concrete and at a muzzle-obstructing wall,
and captures hip/ADS/reload/inspection views. Native validation targets
macOS/Metal. The step-7 fixture additionally covers the animation/ammunition
matrix on release WebGL; physical mobile qualification remains outstanding.

## Framework contract

`main/controller.script` owns one session from `game/runtime.lua`. Every session
has its own mutable state; Lua module tables contain functions and constants.
Systems initialize explicitly in world → player → weapons → AI → FX → audio
order and finalize in reverse order. Optional hooks are `fixed_update(ctx, dt)`
and `update(ctx, dt)`; add them only when the subsystem has work in that phase.

Defold calls `fixed_update` zero or more times before `update`. Each tick applies
queued damage, runs simulation modules, then consumes input edges. Held buttons
persist; presses, releases and mouse deltas survive frames with no fixed tick.
Focus loss clears pending and held input. Defold owns physics stepping.
Frame updates run presentation effects and interpolate previous/current actor
positions. `late_update` applies the camera transform and sends HUD presentation data
to the GUI; interpolation never overwrites the actor's collision transform.
The interpolation clock assumes this bootstrap collection runs at normal time
scale. Collection time scaling will require an explicit clock adaptation.

`game/combat.lua` is the only health/death writer. Systems call
`combat.request(ctx.combat, {target = "player", amount = 25, source = "enemy"})`;
components can post the same payload as `apply_damage` to `/controller#script`.
Hits apply at the beginning of the next fixed tick. Dead or unknown targets and
nonpositive/nonfinite amounts are rejected. Overkill clamps to remaining health,
and death emits once. Each physical hit must be submitted once by its producer.

`game/events.lua` preserves the reference event names for weapon fire/reload/shells,
bullet impacts/tracers, damage, death, footsteps, landing, stance and explosions.
Delivery is synchronous and ordered. Treat payloads as read-only and remove
subscriptions in `final`. In this port **damage events report already-applied
damage**; listeners must never apply it again. Damage payloads contain `target`,
`source`, `amount` (actual damage), `health`, `killed`, `headshot` and optional
`point`. Death contains `actor`, `source`, optional `point` and `impulse`.
FX ignores player damage for hitmarkers. Weapons produce fire, dry-trigger, reload,
shell, impact, travelled-segment and tracer notifications. Impact and segment
notifications share an opaque per-round token for suppression deduplication.
Audio consumes notifications without
applying damage or advancing any gameplay random stream. Future systems supply
their remaining event producers.

Actor, camera, generated mesh batches and structural collision objects are wired.
World batches and collision objects belong to the world module; enemy game objects belong to AI.
Each system must release its generated Defold resources in `final`.

## Generated world

`game/world/layout.lua` is the shared description for geometry, collision,
navigation, cover, room audio, lighting and inspection views. The unrotated map
retains the reference's 9-metre road, 6.5-metre building line, 0.145-metre pavement,
full z=-58..46 street and all 20 building footprints/storey counts. A 168 × 168 m
tiled ground plane supports the alleys and yards; visible outer boundary walls
replace the excerpt-only yard barriers.

Five bidirectional flank routes cover the west courtyard/rear lane, northern
west alley, southern west route, eastern alley/ruin yard and eastern approach to
the far cross street. The street spine passes through the gate and bends around
BS3 into the narrow southern gap. E1 connects its street entrance to the eastern
alley through a second doorway. Eight source spawn anchors are recorded, six
active enemy spawns/patrols cover the expanded map. Cover positions come from
the authored barriers, crates, sandbags and wrecks. Background rows have open ground-floor arcades to
preserve the reference's omitted front facades and keep rear routes traversable.

W2 has one upper apartment; E1 and the existing adapted E2 each have two.
Their five flights use the same tread/opening dimensions for rendering, collision
and navigation. E3 has no reference staircase, so its collapsed upper floor has
no fabricated navigation connection. Step 4 adds the architecture and furnishing
recipes described above. E2's additional interior, simplified collision and the
outer terrain walls are retained Defold adaptations.

Current mesh/collider counts and engine limits are listed in the step-4 resource
account above. Loading copies buffers in 512-vertex slices under a soft 4 ms
work deadline. The measured peak update is reported by `world.snapshot`.
The minimap retains all collider rectangles and reuses at most 256 GUI nodes for
visible geometry (145 at the measured grid peak). It no longer truncates the map
at the first 256 shapes. `world.navigation` returns explicit 32-item pages with
collection totals; `tests/world_navigation.py` reads the complete graph.

`tests/full_market_smoke.py` checks all 196 nodes and 201 edges with real Bullet
capsules in both directions, routes all six actors to 18 destinations, walks all
five flank routes and five stair flights both ways, exercises the new entrances,
gate and south gap, runs live E1/eastern patrols, and saves eight inspection views
under `build/full-market-validation`. `--quick` omits live traversal and patrols.
For browser validation, build debug `wasm-web` with
`--settings tests/market_browser.project` and a bundle directory outside the
reserved `build` folder, then run:

```sh
PLAYWRIGHT_MODULE=/path/to/playwright node tools/validate_market_browser.mjs \
  --bundle="/path/to/bundle/Claude of Duty"
PNGJS_MODULE=/path/to/pngjs node tests/market_browser_pixels.mjs
```

The browser fixture repeats physics and the 108-route matrix and captures the same
views at 1280 × 720. The pixel check verifies that floors and walls actually appear
in the minimap. Step-4 validation receipts are under `build/full-market-validation`,
`build/world-detail-browser-final` and `build/world-detail-native-validation`.
The final native quick run is under `build/full-market-quick-validation`.
These are layout smoke checks; the sustained 60 FPS combat
qualification in parity steps 18–19 remains open.

Enter W2 through the shopfront, cross to the back-left of the shop, and climb
the straight staircase along the west wall. The upper landing leads through
an open doorway into a living/work room and a separate bedroom. The upper floor
is 3.2 metres above the shop, with sixteen 20-centimetre steps, a 1.8-metre-wide
flight and standing headroom throughout. Three solid guards protect the stair
opening. The roof is closed; doorways are open passages, with no moving doors.

Enter E2 through its west-facing shopfront farther along the street. Its staircase
runs toward +Z along the east wall, opposite W2's -Z ascent. The middle landing
opens onto a hallway that also leads back to the next flight. Both upper floors
have a living/work room and bedroom. Thin treads on the second flight preserve
standing headroom on the flight below; the middle-floor entrance remains open,
while the top-floor stair opening has an end guard.

`interior.lua` derives treads, four floor slabs around each opening, upper walls,
partitions, furniture, bounded lights and layered navigation from the layout.
The opening follows the reference W2 stair-hole bounds; interior furnishing and
partition recipes are simplified. Exterior belt trim stays outside the building
so it cannot visually seal the stairwell. Furniture and structural solids share
their mesh/collision dimensions. The shared recipe accepts either entrance side,
either stair direction, multiple storeys and optional per-floor `uppers` layouts.
Eleven bounded room lights also define audio room zones on all five floors.

`recipes.lua` emits boxes from that description. Each structural box produces
both visual triangles and a collision descriptor with a surface identifier.
The shop front consists of separate side walls and a lintel, leaving a genuine
2.8 × 2.65-metre opening in W2 and a 2.4 × 2.65-metre opening in E2. Small window
trim, shelves, canopy fabric and produce are visual detail; tables, crates,
walls and floors have simple solid proxies.

`generator.lua` merges opaque geometry into spatial buckets with per-vertex
surface selection and a 12,288-vertex upload cap. Every batch carries explicit AABB buffer metadata
for Defold's frustum culling. There are no game objects per decorative piece.
Slabs own the top of each storey, and walls/trim use butt joints at corners.
`visible_faces.lua` subtracts buried surfaces and gives coincident outward faces
one owner before triangulation. This removes depth ties at slab edges, trim
undersides and kerbs without changing collision proxies. The original slice generated
519 boxes, 77 mesh batches, 36,552 vertices and 190
collision objects. Vertex streams occupy 1,462,080 bytes (CPU/GPU resource overhead
is additional; the batch count is not a measured per-frame draw-call count).

Loading advances through geometry, mesh uploads, collision creation and a
settling frame before `ready`. Geometry collects recipes, clips faces and indexes shared edge endpoints, then
meshes them, handling at most 4,096 jobs per update across these three stages.
Collision creation and buffer uploads permit up to 128 jobs per update; each
upload job copies at most 512 vertices. A soft 4 ms CPU deadline is checked
between jobs, and a mesh is published only once every vertex has been copied. `world.snapshot` reports total CPU work and the peak loading
update; it excludes shader compilation and other engine work outside these calls.
Factory objects and generated buffer resource references are released on teardown.
The physics component pool is explicitly set to 512 to accommodate the expanded
world, temporary actor replacement and optional traversal/firing fixtures.

Seeded decoration, spawn and weapon streams are independent. The current spawn
points are authored. Changing loading budgets or decorative detail cannot move
collision, spawn points, or advance the gameplay random streams.

Metadata includes floor rectangles with heights and layers, navigation nodes,
bidirectional connections (including the kerb step and doorway), cover candidates,
lights, spawn points and minimap rectangles with vertical bounds. Native
validation checks floor support and clear connection centrelines. These are
navigation inputs, not a finished navmesh or proof of every route's clearance.
The graph has 93 nodes and 93 edges, including every tread, upper doorway and a
street spine joining the two building entrances and both mouths of the west loop.
Ground-floor nodes are namespaced by building (`W2/room`, `E2/room`, plus `/walk`, `/door` and `/street`). E2's second
upper floor uses `E2/floor2/` node IDs.
Actors outside a stair flight attach through its landings; actors already on the
flight can replan through intermediate treads. This prevents the raised clearance
probe from admitting an unwalkable shortcut onto the side of the stairs.

`tests/building_smoke.py` checks continuous player movement between buildings and
all five floors, guards, floor collision, enemy ascent/descent and W2 alerted
pursuit upstairs. It also patrols an enemy from W2 to E2's second-floor bedroom
and back. `--ai-only` runs navigation/combat checks; `--e2-only` limits the run to
the cross-building/E2 increment, and `--w2-only` runs the original W2 checks.
It uses the Automation Bridge's `ui.focus` callback simulation and explicit resume when the
desktop loses focus, allowing long tests to run in the background. Normal game
focus behavior is unchanged. Review captures are written to
`build/building-validation`. `world.navigation` exposes the generated graph;
`world.view` accepts `stairs`, `upstairs`, `e2_shop`, `e2_stairs`, `e2_upstairs`
and `e2_top` in addition to the original views.
The world Lua tests also verify standing headroom, connected floors, the minimap's
stair opening and its bounded rectangle count. This building increment targets
native macOS/Metal validation; browser/mobile validation remains outstanding.

`tests/market_smoke.py` walks the complete market circuit in both directions,
checks actual dirt/cover collision, patrols the enemy around the loop and tests
alerted pursuit around W2's occluding corner. `--ai-only` skips player traversal;
`--views-only` captures and profiles the four review views. It writes screenshots
and `costs.json` to `build/market-validation`. `world.view` also accepts `courtyard`,
`rear` and `alley`. The Lua checks verify both independent paths, continuous ground
and standing capsule clearance along every new edge, cover clearance, deterministic
loading and the existing GUI/resource budgets. The 77 world batches are up from
50; stream storage was about 0.71 MiB, up from 0.51 MiB, before face clipping
raised it to 0.80 MiB. Matching trim/slab edge subdivisions now bring it to
1.39 MiB (36,552 vertices); the 77 batches and 190 colliders are unchanged. The existing mesh, physics,
GUI, texture and render-target limits are unchanged. A macOS/Metal debug run at
1920 × 1280 measured 29.1 ms of world-loading CPU work (1.03 ms peak job). Short
90-frame inspection captures reported 154 submitted draws for the street, 121
for the courtyard/alley and 131 behind W2; these include shadows, post-processing
and GUI. `DrawRenderList` averaged 0.83–1.01 ms of CPU time across those views.
That pre-HDR run used an estimated 50.5 MiB for nine render targets; the current
HDR path uses 70.5 MiB at this resolution. These idle views do
not establish GPU timing, sustained combat performance or browser/mobile budgets.

Generated world materials now sample runtime GPU atlases and receive the lighting,
shadows and height fog described below. Room lights are sourced from the same
world metadata and clipped to the interior bounds.

## Rendering reference captures

Rendering step 1 now provides an opt-in, versioned visual baseline. It freezes
gameplay without altering its state, hides HUD/actors/effects, sets exact camera
poses and vertical FOVs, and uses fixed hip/ADS rifle poses. Normal rendering and
settings return on `capture.end` or Escape. Capture requires the debug Automation
Bridge; ordinary play does not allocate the laboratory.

```sh
PYTHONPATH=automation-bridge-python python3 tests/render_baseline.py --motion --profile
PYTHONPATH=automation-bridge-python python3 tests/render_baseline.py --launches 3
```

Requires Pillow and an open Defold editor. `ffmpeg` is optional for MP4 encoding;
the PNG sequence is always retained. Outputs go to a new timestamped directory
under `captures/rendering`, or a new directory passed with `--output`. Captures
are ignored by Git and kept outside `build` so a clean build preserves them.
The harness produces 1280 × 720 images at actual framebuffer resolution, including
on HiDPI displays, and verifies exact repeat pixels after changing cameras away
and back. It records camera/FOV, source revision and source hash, renderer settings,
seed, resource estimates, engine metadata, and optional CPU scopes/draw counters.
These profiles are frozen views, not GPU timing or sustained combat measurements.
The contact sheet is `contact-sheet.jpg`; complete metadata is `manifest.json`.
`--launches 3` starts three independent engines and asserts exact RGB equality
for every supported shot, recording `repeatability.json` and separate per-launch
manifests. The overlapping wall/slab and trim surfaces have been repaired and
buried faces clipped. Shared trim/slab edges also use matching endpoints to
prevent one-pixel depth ties at grazing angles. No pixels are masked or tolerated.
Catalogue version 12 contains 56 shots and retains the 0.1–500 m world clip
range; the 0.1 m near plane improves depth precision while remaining inside the
player's wall clearance. The separate weapon clip range is unchanged.

The catalogue in `game/render/capture.lua` has street, interior, detail, courtyard,
weapon, ADS and laboratory captures, plus fifteen material close-ups, near/mid/far façade views and a grazing
road view. Daylight (16:30), sunset (19:12) and night (01:30) use the reference's
45° N summer-solstice celestial model, rotated 61° into this partial map. These
are fixed solar-time states, not the computer's clock. The catalogue also includes
cloudy sky views, a clear lunar close-up and a room with a real window aperture.
The reference world rotation/framing still differs; this is not a cross-engine
pixel or full scene-parity claim.
The generated laboratory has fifteen surface panels, a floor, a corner with crates,
a table and two sphere rows: rear dielectric, front metal, with roughness
0.08/0.25/0.5/0.75/1 from left to right. It uses the production world shader and
shadow pass; uniform sphere parameters isolate lighting from the texture recipes.
Its 31 meshes are released on exit; the shadow fixtures include a perforated
panel and a remote floor/occluders 160 m from the street. The reflection fixture
plate shares visibility clipping and edge stitching with its box and floor,
avoiding depth ties at the reflected contact. The additional enclosed room has
an open window, solid sill/lintel/jambs, a mullion and a freestanding occluder.
It reuses existing material batches, preserving the 31-mesh fixture budget.

The optional laboratory, grazing-road, weathered-façade, shadow-distance and
cutout-shadow sweeps each contain 121 frame-addressed camera samples at 30 FPS. Screenshot transport never advances gameplay or the sweep;
`capture.frame` explicitly selects each pose. Their MP4s are for visual stability
review and do not measure real-time frame pacing.

Capture the local Three.js source with its own deterministic 90-frame shutter:

```sh
# In the reference checkout first: npm ci --ignore-scripts
node tools/capture_reference.mjs --source=/path/to/Claude-of-Duty-main --baseline=/path/to/defold/manifest.json --repeats=2
python3 tools/compare_render_baselines.py /path/to/defold/manifest.json /path/to/threejs/manifest.json --output captures/rendering/comparison
```

The reference tool uses Playwright from that checkout (its Chromium must be
installed), starts/stops its own Vite server, and leaves source files untouched.
It transforms the same level-space cameras through `world.levelToWorld`, matches
resolution/FOV and records the reference's Ultra settings, fixed seed and source
hash. Each shot boots afresh to avoid inherited temporal history. Reference shots
use 16:30 daylight, 19:12 sunset or 01:30 night. The generators, partial map and
lighting differ, so these are visual comparisons, not cross-engine pixel tests.
The comparison tool also accepts two Defold manifests for later regression review.
The adapter exports the production laboratory geometry, selects the requested
weapon and solar time, and records actual exposure/renderer state. Glass, cutout,
local-light and transient combat fixtures remain explicitly pending. The hosted
Kaigen demo runs as an observational reference; controlled captures and a matching
laboratory remain unavailable because the local archive lacks its engine and the
hosted build has no verified capture adapter. See the versioned
[parity contract, source lock and reproduction guide](parity/README.md) for the
24 acceptance scenarios, limitations, and Mac/desktop-browser 60 FPS targets.

Automation commands: `capture.catalog`, `capture.shot {name}`, `capture.snapshot`,
`capture.frame {frame=0..120}`, and `capture.end`. Settings reset to the baseline
defaults while capturing and are restored on exit. A restart exits capture mode.

## Generated materials and rendering

The GPU now generates fifteen material recipes plus one shared microdetail set.
All recipes are adapted from the reference material library, with deterministic
seeds, linear albedo, height, physical-scale Sobel normals and packed
roughness/metalness/occlusion. Concrete flooring has saw-cut joints and power-float
variation instead of wall formwork. Brushed metal, chipped paint and insulating
rust use separate responses. Fabric has warp/weft, folds and pulled threads;
rubber has pebble grain, scuffs and mould seams; glass has smears and water spots.
The glass recipe panel remains an opaque material preview. Step 9 uses that recipe
on separate transparent panes, including the two shop display cases. Thin panes
use Fresnel reflection and transmission; refractive distortion is not implemented.
Weapon/soldier material expansion is implemented in step 11; see the combat rendering section.

| Recipe | Tile width (m) | Height relief (m) |
| --- | ---: | ---: |
| Plaster | 2.2 | .060 |
| Asphalt | 3.0 | .075 |
| Wood | 2.0 | .038 |
| Brushed metal | .8 | .004 |
| Fabric | .7 | .008 |
| Concrete wall / floor | 2.5 | .090 / .075 |
| Brick | 1.35 | .055 |
| Tile | 1.5 | .030 |
| Dirt | 2.5 | .120 |
| Gravel | 1.6 | .055 |
| Painted metal | 1.5 | .018 |
| Rusted metal | 1.2 | .035 |
| Rubber | .5 | .013 |
| Glass | 2.0 | .0008 |
| Shared microdetail | .25 | .0034 |

These are height-field ranges, not displacement of the geometry. Two RGBA8 alpha
channels preserve height precision for baking normals. Albedo and packed data
stay linear; sRGB mesh tints are converted once. Floors/stairs use the slab
recipe, counters use tile, boundary walls use brick, shops use painted metal,
crate straps use rust, and the west rear lane uses gravel. Dirt has its own recipe.
Collision surfaces, navigation and dimensions are unchanged by these assignments.

`render.material_quality` selects a **launch-time** preset. `medium` is the project
default; override it with `--config=render.material_quality=low` or `high`.
Large recipes and microdetail use 256/512/1024 pixels for low/medium/high;
brushed metal, fabric, rubber and glass use half that resolution. Physical scale,
recipe IDs and seeds stay fixed. Low disables parallax. High is an opt-in desktop
preset: its atlas requires a maximum texture dimension of at least 5408 pixels.

A deterministic shelf packer places every mip and its periodic one-texel border
in three data atlases. Every recipe has its full chain to 1×1; short chains clamp
their final level. Trilinear sampling, two taps along the major footprint axis and
normal-variance roughness correction reduce minification shimmer. Bake FBM
frequencies follow the preset resolution. Shared micro albedo/normals fade with
both distance and pixel footprint. Selective 12-step parallax uses fixed explicit
LOD and fades near silhouettes, at grazing angles and beyond six metres. It
changes sampling only, not depth, collision or shadows.

Rendering step 4 adds metre-scale discolouration, sparse repair patches, runoff
from visible wall tops/ledge cuts, ground splash, upward-facing dust, cavity grime
and narrow edge wear. Low-frequency warping is restricted to unstructured
materials, preserving plank, brick and tile layouts. All variation uses world
coordinates; there is no camera-dependent randomness. Interiors have reduced
weather exposure. Mesh streams retain colour and add original face-edge distances
plus wear/grime/occlusion weights and runoff source height. Ground chunk seams
have zero wear/contact masks; visibility cuts cannot introduce fake worn edges.
Mesh contact occlusion combines with baked cavities using their maximum, rather
than multiplying them and darkening a cavity twice.

Loading fills an 896-command budget per update, including recipe, copy and filter
jobs. Scene rendering starts on the update after baking completes. The environment is one complete 128-sample bake
pass at the end of loading; it is never rebuilt during normal play. Defold's discard-on-load targets need
full-atlas preservation before partial updates. The two scratch targets and spare
atlas are released after queued bake draws finish: twelve targets during loading,
nine in normal play. Resize/restart do not rebake. The context callback schedules
a map rebake; see the browser recovery limitation below. No material or weather generation consumes gameplay RNG.

Rendering step 5 uses `game/render/daylight.lua` as the single linear-light rig
for the direct sun, shadow direction, visible sky, diffuse environment and
reflections. World geometry, soldiers and camera-transformed weapons share GGX
lighting with matching Smith visibility. The visible solar disc is excluded from
the environment convolution because the direct sun already supplies its highlight.

The runtime-generated 396 × 594 environment atlas contains six 64² cube faces
with one-texel direction gutters per tile. Its rows hold the visible sky, six GGX
roughness levels (0..1), cosine-convolved diffuse irradiance divided by pi, and a
linear two-channel integrated BRDF lookup. Deterministic 128-sample Hammersley
integration runs at load; shading interpolates adjacent roughness levels and
uses the split-sum response. This follows the standard IBL derivation described
in [Filament's lighting reference](https://google.github.io/filament/main/filament.html#lighting/imagebasedlights).
Explicit tiles avoid backend-specific writable mip attachments and keep the
existing sampler and target counts. The BRDF row is data, never radiance-encoded.

Generated building footprints attenuate indirect diffuse, specular and sky-lit
fog throughout both enterable buildings, including their upper floors. A wall
feather preserves the exterior face; the roof surface stays outdoors. Doorway
fill falls off smoothly into the shop. Two matching awning volumes reduce sky
fill under the canopies while preserving their open sides. The deep-interior
floor is tuned to 0.18 for this renderer's fixed exposure; closed upper windows
admit no additional sky. Cooler sky fill, warm ground bounce and bounded room
lights remain distinct. These are coarse authored visibility volumes, not GI or
per-prop occlusion; step 7 supplies screen-space AO/contact detail. The eight-volume limit
is checked explicitly and is independent of room-light selection. The laboratory
ignores world volumes so its overlapping test geometry remains neutral.

Up to four authored room lights remain active. Distance to room bounds ranks
candidates, with hysteresis for incumbents and persistent slots. Replacement lights
fade through zero energy over 0.18 seconds per phase, without moving a light through
a wall. Camera teleports and capture entry reset selection immediately. A separate
selection chooses the two most relevant active lights for shadows, using the same
hysteresis and fading. Bounds prevent room light from crossing exterior walls/floors.
The soldier retains procedural camouflage; weapon vertex colours carry metalness.

Rendering step 6 replaces the fixed street shadow map with four 1024² cascades
in one 2048² RGBA8/depth atlas. Camera-depth splits are 8, 22, 52 and 120 metres;
the last 12% of each slice blends into the next, with a final fade to unshadowed
beyond 120 m. Fits include the preceding blend band and an 80 m upstream caster
margin. Bounding-sphere extents remain constant under camera rotation; light-space
centres snap in all three axes to whole texels. A 12-texel guard contains the
normal offset and filter footprint, and every tap clamps to its own atlas tile.
The displayed interpolated camera drives fitting, including ADS, inspection,
teleports, laboratory captures and aspect-ratio changes.

Static/capture batches are cached in four 1024² colour/depth targets. A cached
projection is reused only while it contains the camera slice, its filter guard
and the 80 m upstream caster margin; light direction and texel scale must match.
The cached matrix travels with its pixels. Camera motion can therefore reuse
static geometry without delaying a shadow update or changing resolution.
Teleports, capture changes, settings changes, world readiness and context
restoration invalidate the cache. `shadow_cache=false` selects the original
uncached path for direct comparisons.

Each frame copies the cached colour **and actual depth attachment** into the
combined atlas, then draws animated soldiers with that cascade's light frustum.
The colour and shadow passes share the soldier's 25-bone
skinning and the world's procedural binary-coverage function. Vertex alpha of
one stays solid; lower world alpha opens circular holes on a 30 cm grid. Soldier
alpha remains camouflage weight. A laboratory panel checks matching visible
holes and projected shadows. The complete atlas clears once per frame, including
when shadows are disabled; all four tiles draw in that same render pass so tile
GPUs retain earlier cascades.

Caching adds 32 MiB and four targets (43 steady targets with current defaults).
It retains every caster, four 1024² cascades, the 120 m range and the original
PCSS filter. At native 1920 × 1280, repeated paired moving-camera samples measured
76.5 → 83.1 FPS on the street (530 → 273 draw calls), and 75.3 → 80.8 FPS in the
distance view (524 → 285 calls). These are short CPU frame-scope measurements
with live TAA and frozen gameplay, not sustained combat or GPU timings; they do
not establish 120 FPS. Nine matched stills differed by at most 2/255 per channel,
on at most 137 pixels out of 2,457,600. Twenty-one moving-camera comparisons with
TAA disabled also passed: mean channel differences stayed below 0.038/255, with
fewer than 0.01% of pixels differing by more than 8/255. Run
`PYTHONPATH=automation-bridge-python python3 tests/shadow_cache_smoke.py` for
paired stills, motion without TAA and repeated cache-on/off profiles.

Sun visibility uses geometric normals for world-unit normal/slope bias, packed
16-bit depth, eight blocker taps and nine bilinear comparison taps (36 texture
reads) for bounded contact-hardening softness. Kernels stay fixed in light space;
there is no screen-noise rotation to shimmer before TAA. Close blockers remain
sharp, distant blockers soften with a 0.022 sun-radius factor, capped at four
texels. This is a bounded approximation to the reference PCSS, not exact renderer
parity. Step 9 adds the separate local-light shadow budget described below.

Rendering step 7 adds a full-resolution world prepass with the same static geometry,
25-bone skinning and binary cutout coverage as colour/shadows. RGBA8 stores
16-bit logarithmic view depth in RG and octahedral geometric view normals in BA;
its separate depth attachment resolves visibility. Nearest sampling and explicit
sky coverage work on both Metal HDR and the WebGL compatibility pipeline.
Weapons and GUI are excluded; step 8 also supplies rigid-effect depth.
Material normal maps stay in the colour pass, avoiding false occlusion from small surface bumps.

Half-resolution AO integrates horizon arcs over four fixed slices with six
quadratically spaced samples on each side, within a 0.85 m radius. Short contact
rays take twelve steps over 0.4 m toward the current sun, with normal/depth bias,
12 cm thickness rejection, distance falloff and screen-edge fading. A joint 3×3
bilateral resolve uses full-resolution normals and surface-plane distance to
filter and upsample both channels. Incompatible thin-edge samples fall back to
lit visibility; sky remains white. Offscreen/hidden occluders cannot contribute.
Fixed samples are deterministic but retain some spatial banding in the isolated
AO view; step 8 accumulates the resulting world radiance over time.

AO affects indirect diffuse and roughness-weighted indirect specular. Taking the
minimum of material cavity visibility and screen AO prevents multiplying the
same cavity twice. Contact visibility takes the minimum with cascaded sun
visibility and affects only direct sunlight; local room lights retain their
existing response. The weapon samples neither screen-space effect.
`ambient_occlusion` and `contact_shadows` independently toggle the effects; both
off skips AO/contact draws; the prepass remains necessary while TAA or a depth
diagnostic is enabled.
Buffers are cleared to lit visibility when disabled and retain bounded ownership.

Rendering step 8 adds an eight-sample Halton projection jitter and two alternating
HDR/compatibility colour histories. The expanded prepass writes three portable
RGBA8 attachments: current depth/normal, two 16-bit signed UV motion components,
and the corresponding previous depth/normal. Two alternating prepass targets
retain visibility from the previous frame. Static geometry uses previous camera
matrices; soldiers retain the previous displayed root transform and all 25 bone
matrices. Rigid particles, tracers and cases retain their own prior transforms.
The extra mesh components share their existing generated vertex resources.
The laboratory uses the production face-clipping and edge-stitching routines
at table/floor joints; subpixel jitter exposed an instability in its old boxes.

The resolve removes projection jitter, reprojects geometry and sky, rejects
incompatible depth/normal samples per bilinear tap, and clips history to a 3×3
variance neighbourhood in luminance-compressed YCoCg. Motion and radiance changes
reduce history weight. Explicit teleports, camera cuts, encounter restarts,
projection jumps, setting changes, resize and context restoration invalidate it.
Previous pose data is owned per actor; the viewmodel never samples world history.
`temporal_aa` and `weapon_aa` are independent Display-menu/automation settings.
The weapon uses spatial edge-directed antialiasing in premultiplied linear light,
with decode-before-filtering on the encoded path, and is composited after world
TAA/bloom. It has no temporal history or projection jitter.

`view="motion"` displays signed velocity around neutral grey (±4 pixels fills
one colour channel); `view="history"` displays the accepted history weight.
`renderer.snapshot` reports history age, reset count/reason and AA pass counts.
After two current-only frames for camera/component transforms to settle, ordinary
captures converge for exactly 32 history samples, then hold
the result, preserving frame/order-independent comparisons. `capture.frame`
resets that convergence for independently addressed samples. For continuous
history, select `capture.shot` with `temporal_live=true`; `capture.play` with
`playing=true` runs a repeating 0–120–0 frame camera sweep, and `playing=false`
stops it. Continuous captures must be used when profiling TAA: held captures
skip the resolve. `tests/temporal_smoke.py` exercises both paths, motion vectors,
weapon isolation, exact resets and short A/B CPU/draw costs.

Rendering step 9 adds a current-frame screen-space reflection resolve. The opaque
pass exports shaded world normals/roughness and the existing indirect specular
weight into two RGBA8 attachments. Smooth surfaces trace at most 48 steps over
24 metres, with five refinement steps at the first depth crossing. Thickness,
backface, distance, roughness and screen-edge rejection blend toward the existing
roughness-filtered environment. The resolve replaces the environment contribution
with matching BRDF, interior, cavity/AO and fog weights, rather than adding another
highlight. It runs before world TAA; its input never contains its own output.
Offscreen/hidden surfaces, transparent panes and multiple reflection bounces cannot
appear in this screen-space solution. Rough surfaces retain environment lighting.

Two 256² six-face point-shadow maps share one 768 × 1024 RGBA8/depth atlas. A
single clear/render pass preserves every tile on tile GPUs. Static and skinned
casters share production cutouts and skinning; packed radial depth and a bounded
3 × 3 comparison filter provide local occlusion. Every face has its own frustum.
The remaining room lights and transient muzzle flashes are unshadowed. Each flash
comes from a real player/enemy firing event, lasts at most 60 ms and shares a
separate two-light budget. The player's displayed muzzle is transformed into world
space and clipped against walls. Capture mode suppresses live flashes; restart
clears them. None of these presentation systems consume gameplay RNG.

Glass uses individual centred, two-sided pane objects, sorted back-to-front by
Defold. Opaque depth rejects hidden fragments. Procedural smudges/normals, dielectric
Fresnel reflection, scalar absorption and restrained tinted dust scatter give the
thin panes a distinct response. They do not cast solid shadows or enter opaque
SSR/history. After world TAA, glass accumulates premultiplied linear light in its own
target and composites over the world. The RGBA8 compatibility layer stores linear
radiance divided by eight so blending never operates on square-root encoded light.
The separate weapon still composites last. Intersecting glass and refractive
transmission are outside this thin-pane path.

Pass order is sun cascades → two point-shadow cubes → depth/normals → AO/contact
→ sky/world → reflections → shadowed atmosphere → world temporal resolve
→ isolated weapon AA → sorted glass/effects → world motion/ADS blur → exposure
meter → multiscale bloom → world/weapon composition, sharpening, exposure and
vignette → AgX → sRGB conversion → generated grade, grain and dither → GUI.
Metal uses linear RGBA16F radiance; authored vertex colours use the piecewise
sRGB transfer function and generated atlas values are linear albedo. Weapon
flashes participate in metering/bloom. The weapon remains separate from world
fog, temporal history and optical blur. GUI stays outside the photographic chain.
See rendering step 12 below for controls and qualification.

Other backends retain the square-root encoded 0..8 RGBA8 compatibility path until
float renderability, filtering and blending are qualified there. The presence of
`graphics.TEXTURE_FORMAT_RGBA16F` alone is insufficient. Set `hdr = rgba8` under
`[render]` (or use engine argument `--config=render.hdr=rgba8`) to force that path
on Metal; the default is `auto`. Both paths share AgX and sRGB conversion.
`renderer.snapshot.pipeline` records the selected format, backend and reason.
`game.project` sets the default
GLSL ES float precision to `highp` for noise, packed shadows and lighting. Using
the project setting also keeps precision declarations ahead of Defold's generated
fragment output in WebGL shaders.

At the 1280 × 720 capture size, estimated HDR target storage is:

| Preset | Atlas size | Steady / bake peak (MiB) | Bake jobs / draws |
| --- | --- | ---: | ---: |
| Low | 1024 × 1368 | 159.54 / 165.38 | 825 / 1245 |
| Medium | 2048 × 2712 | 207.07 / 230.26 | 921 / 1389 |
| High | 4096 × 5408 | 397.01 / 489.51 | 1017 / 1533 |

The environment added 1.61 MiB on HDR (0.80 MiB on the compatibility path)
in step 5. Step 6 adds 24 MiB for cascaded colour/depth storage on both paths.
Step 7 adds 11.43 MiB at this size for the full-resolution prepass and resolved
occlusion plus half-resolution raw occlusion. Step 8 adds 42.19 MiB on HDR
(31.64 MiB on the compatibility path) for motion/previous-depth attachments,
colour histories and weapon AA. AA toggles skip their resolves/jitter but retain
allocated targets and the motion attachments used by the prepass.
Step 9 adds 34.13 MiB on HDR (23.58 MiB on encoded RGBA8): two material
attachments, three colour targets and the point-shadow atlas. The new toggles
skip their draws while retaining allocations. Ownership is twenty steady targets
and twenty-three during baking. World materials gain a local-shadow sampler. Four static and
four skinned shadow submissions replace the previous one of each, with per-cascade
frustum culling; frozen captures omit the skinned submissions. These material
presets currently share the same shadow resolution; mobile budgets remain open.
The previous six-recipe implementation used 102.49 / 134.60 MiB at this size.
These are allocation estimates including conservative 32-bit depth, excluding
meshes and driver overhead; they are not measured process peaks. The world now
uses 88 opaque/glass batches, 36,564 vertices, 2.51 MiB of mesh streams and the
same 190 colliders. Resize affects fourteen screen-sized targets; zero-sized
windows skip drawing and finalization releases owned targets.

`renderer.snapshot` reports cascade splits, world texel sizes, atlas dimensions and
shadow submissions (static refreshes, depth copies and dynamic draws separately),
cumulative cache refreshes, temporal history/reset status and AA passes, plus bake
jobs/draws, current/peak target bytes, local-light count,
shadow frames, environment dimensions/levels/sample count, volume count and active settings.
It also reports prepass/effect submissions, occlusion dimensions, sample counts,
metre-space radius/ray length and the depth/normal format. `renderer.configure` accepts booleans
`reflections`, `glass`, `local_shadows`, `muzzle_lights`,
`temporal_aa`, `weapon_aa`, `ambient_occlusion`, `contact_shadows`, `shadows`, `normal_maps`, `local_lights`, `fog`, `bloom`, `weathering`,
`micro_detail`, `parallax`, `interior_lighting`, `environment_filter`; numeric `exposure` in
0.25..4; and `view` equal to `scene`, `albedo`, `normals`, `material`, `shadow`,
`environment`, `environment_atlas`, `cascades`, `shadow_visibility`, `hdr_probe`,
`depth`, `geometry_normals`, `ao`, `contact`, `occlusion_raw`, `motion`, `history`, `reflections`, `local_shadow` or `glass`.
`reflections` shows accepted ray confidence, `local_shadow` shows all twelve point-shadow
faces and `glass` shows the raw transparent layer. Snapshots report these pass
counts, the ray/shadow budgets and current/cumulative muzzle-light frames.
`depth` shows logarithmic camera depth (white sky); `geometry_normals` shows
view-space geometry normals (black sky). `ao`/`contact` show resolved visibility;
`occlusion_raw` shows unfiltered AO in red and contact in green.
`shadow` shows all four atlas tiles; `cascades` colours the receiver slices and
blend bands; `shadow_visibility` isolates sun visibility. `hdr_probe` renders diagnostic HDR stripes into
the actual scene/weapon targets and displays transfer/filter/blend samples.
`environment_level` chooses the equirectangular debug row: 0 is visible sky,
1..6 are specular roughness levels and 7 is diffuse. `environment_atlas` shows
all tiles and the raw BRDF row. `environment_filter=false` uses the sharpest
reflection level for A/B checks; `interior_lighting=false` bypasses volume gates.
`atlas_half` retains the legacy half-atlas view. `atlas_page` selects 1024²
windows (1-based, row-major from the bottom left; 0 restores the full atlas),
allowing exact texel inspection within desktop window-size limits.
Configuration applies on the next render message dispatch, so tests
wait for the snapshot to reflect it. All controls affect presentation only.

The Lua suites cover loading budgets, target ownership, context rebakes, every
preset's mip packing, physical parameters, mesh masks and deterministic generation.
Native GPU checks inspect every mip/border and recipe channel; feature-toggle
comparisons check weathering, microdetail, parallax, distance fading and exact
pixel restoration after camera motion. The capture catalogue includes every
material close-up, near/mid/far laboratory and façade views, plus laboratory,
grazing-road and façade sweeps. Repeated-launch comparisons use every RGB pixel.

```sh
PYTHONPATH=automation-bridge-python python3 tests/materials_smoke.py
PYTHONPATH=automation-bridge-python python3 tests/weathering_smoke.py
PYTHONPATH=automation-bridge-python python3 tests/lighting_smoke.py
PYTHONPATH=automation-bridge-python python3 tests/reflections_smoke.py
# After a current native editor build; launches its own low/high engines:
PYTHONPATH=automation-bridge-python python3 tests/material_presets_smoke.py
PYTHONPATH=automation-bridge-python python3 tests/render_baseline.py --launches 3 --motion --profile
```

For WebGL, bundle debug `wasm-web` with `--settings tests/rendering_browser.project`.
Then run `tools/validate_rendering_browser.mjs --bundle=/path/to/bundle` with
Playwright installed (`PLAYWRIGHT_MODULE` can specify its module path), followed
by `PYTHONPATH=automation-bridge-python python3 tests/rendering_browser_pixels.py`.
Both tools accept `--output` for a separate capture directory; the browser harness
also accepts `--browser=/path/to/chromium` to reuse an installed executable
and `--timeout-ms=600000` to set the overall validation deadline. The fixture exercises all recipes,
feature toggles, exact atlas pages, interior gating, reflection filtering, laboratory
volume isolation and camera return.
The browser harness records the actual GPU/backend and disjoint timer queries
when available, including short samples per shot. The browser still uses the
encoded RGBA8 compatibility pipeline; this does not qualify floating-point HDR.

The previous step 3–4 debug bundle failed forced WebGL context recovery:
restoration aborted in `OpenGLSetRenderTarget` with
`GL_FRAMEBUFFER_UNSUPPORTED` before generated resources could be recovered.
Step 5 does not requalify forced context recovery. The
separate `context-loss-report.json` retains the failed qualification; reproduce
with `--context-loss=1`. Normal browser captures pass without injecting context
loss. The Lua rebake scheduling test is not proof of real context recovery.

Physical mobile devices, other native backends, mobile thermal/memory limits and
sustained-combat GPU budgets remain unqualified. These desktop/browser material
checks do not close those platform-wide gates or claim full source visual parity.

The step 3–4 validation run passes 137 Lua checks, all three native atlas presets
and 53 WebGL capture stages. All 31 supported native views have identical pixels
across three independent engine launches; the laboratory, grazing-road and façade
sweeps each contain 121 frames. Local comparisons, timing samples and platform
limits are recorded in
`captures/rendering/surface-weathering-review/report.md`.


Step 5 validation passes 140 Lua checks, native rendering/HDR suites and
`tests/lighting_smoke.py`. GPU assertions cover dark-room attenuation with an
unchanged bright doorway, laboratory isolation, filter contributions, raw BRDF
endpoints, all cube edges and exact A/B restoration. Sampled cube seams differ
by at most 0.51 of an 8-bit display value. All 31 existing views are pixel-identical
across three native launches; all three 121-frame sweeps are recorded. The
57-stage WebGL run also passes map, lighting-toggle and exact camera-return
checks on Chromium / ANGLE Metal / Apple M3 Pro.

Local artifacts from this increment:

- `captures/rendering/lighting-final`: final stills, motion samples, source fingerprints and profiles.
- `captures/rendering/lighting-review`: labelled step-4/step-5 comparisons and `costs.json`.
- `captures/rendering/lighting-vs-threejs`: adapted reference comparisons, with geometry/time-of-day differences retained.
- `captures/rendering/lighting-validation/report.json`: native lighting pixel gates.
- `captures/rendering/lighting-browser`: WebGL images, GPU queries, pixel validation and local-build provenance.

Native street draws remain 158 and render-script median CPU remains 54 µs.
The short 1024² browser street sample changes from 3.31 to 3.76 ms median GPU;
interior/laboratory medians are 3.13/3.55 ms. Separate-run timing samples include
whole-frame work and noise; sustained combat and mobile qualification remain open.


Step 6 validation adds five shadow-fitting tests (145 Lua checks total), the
native renderer suite including animated soldier shadow deformation, and
`tests/shadows_smoke.py`. GPU checks cover every atlas tile, remote receivers,
projected cutout holes versus solid cells, effect disable/re-enable, camera/FOV
changes and resize return. All 34 native captures match every RGB pixel across
three independent launches; five sweeps contain 121 frames each. At street
capture FOV/aspect, near-cascade texels are about 2.5 cm versus 6.25 cm previously.

The WebGL 2 compatibility path passes 67 stages plus map/feature/return checks,
all four atlas tiles, remote shadow coverage and projected cutout-hole assertions
on Chromium / ANGLE Metal / Apple M3 Pro. At 1024² the short street GPU sample is
6.25 ms median versus the step-5 sample's 3.76 ms; interior/laboratory are
4.76/4.38 ms. Browser resources match the final native source and use the cached
debug engine. Forced context recovery was not requalified.

The street's frozen native draw count rises from 158 to 398; render-script median
CPU rises from 54 to 85.5 µs. `captures/rendering/shadows-review/costs.json` records
the scope and full comparisons. These separate short runs do not establish
sustained combat or mobile budgets. New artifacts are:

- `captures/rendering/shadows-final`: three-launch repeatability, stills, sweeps and native profiles.
- `captures/rendering/shadows-review`: labelled before/after stills, motion samples and cost comparisons.
- `captures/rendering/shadow-validation`: atlas/visibility diagnostics, projected cutout samples and native GPU report.
- `captures/rendering/shadows-browser`: WebGL captures, GPU queries and build provenance.


Step 7 validation passes 146 Lua checks, the native renderer/HDR suites and
`tests/occlusion_smoke.py`. Pixel gates verify unit view normals and projected
log depth, lit sky/open floor, occlusion beside a table foot, a short sun contact,
actual cutout holes, animated soldier depth, independent toggles and exact camera,
resize and motion returns. All 36 native captures match every RGB pixel across
three launches; the five 121-frame sweeps remain reproducible. The 89-stage
WebGL 2 compatibility run passes the same projected-contact/cutout checks,
material regressions and exact camera return on Chromium / ANGLE Metal / M3 Pro.

New artifacts are:

- `captures/rendering/occlusion-final`: three-launch stills, five sweeps, source fingerprints and native profiles.
- `captures/rendering/occlusion-review`: labelled step-6/step-7 comparisons and rendering costs.
- `captures/rendering/occlusion-validation`: native depth/normal/AO/contact diagnostics, projected samples and A/B costs.
- `captures/rendering/occlusion-browser`: WebGL captures, pixel checks, GPU queries and build provenance.

The frozen native street adds 70 draws (398 → 468). Render-script CPU samples
vary with scheduling, so short-run differences are not treated as a speedup or
stable percentage. Target storage increases by 11.43 MiB at 1280 × 720 on either
colour pipeline. Browser timing scope and before/after samples are recorded in
`captures/rendering/occlusion-review/costs.json`. Physical mobile, other native
backends, forced browser context recovery and sustained-combat budgets remain
unqualified. These checks do not qualify WebGL floating-point HDR.

Step 8 passes 152 Lua checks and the native renderer, HDR, occlusion, soldier,
UI and temporal suites. The temporal checks verify static jitter cancellation,
camera and skinned movement, accumulated history, independent weapon AA, exact
camera/resize/toggle returns and restart/teleport invalidation. All 36 supported
stills match every RGB pixel across three independent launches. A 61-image
frame-addressed sweep retains continuous history; capture latency can add held
frames, so its movie is a visual comparison rather than a real-time benchmark.

The WebGL 2 encoded compatibility run passes 97 stages, including all material,
shadow/contact and temporal pixel checks, with exact camera return. Diagnostic
values bypass radiance encoding and have a separate output, so they never enter
colour history. On Chromium / ANGLE Metal / Apple M3 Pro, separate 18-frame GPU
windows at 1024² measure 6.55 ms median with TAA off and 6.25 ms live; their
variance is too large to infer a speedup. See `temporal-review/costs.json` for
scope and percentiles. These results do not qualify WebGL floating-point HDR.

The continuous street A/B sample has 470 draws with both AA passes enabled and
468 disabled; render-script median CPU is 122.5/96 µs respectively. This short
sample is not a sustained combat or GPU-time budget. The soldier adapter now
uploads its three palettes and previous-root matrix with four Lua calls per actor;
physical mobile and other native
backends remain unqualified. Browser context restoration and floating-point
HDR remain the earlier open gates.

- `captures/rendering/temporal-final`: three-launch stills, fingerprints and held-capture profiles.
- `captures/rendering/temporal-validation`: motion/history diagnostics, returns, independent-AA checks, continuous sweep and live-resolve A/B costs.
- `captures/rendering/temporal-review`: labelled comparisons, cutout motion movie and `costs.json` with measurement scope.
- `captures/rendering/temporal-browser`: WebGL compatibility captures, pixel checks, GPU samples and local-build provenance.

Step 9 passes 157 Lua checks and the native renderer, HDR, temporal, occlusion,
combat, UI and reflection suites. The new checks cover reflection hits and edge
fallback, glass transmission, local-shadow toggles, exact feature restoration,
continuous camera history and real muzzle-light events/expiry. All 39 supported
stills match every RGB pixel across three fresh engine launches. The reflection
fixture shares clipped/stitched box edges with its floor to avoid depth ties.
The WebGL 2 encoded compatibility path passes 107 stages and the material,
shadow/contact, temporal and new feature pixel checks.

With live TAA at 1280 × 720, a short native Metal street sample increases from
470 to 767 draws when all four new effects are enabled; median render-script CPU
is 109/137 µs disabled/enabled. Separate 350 ms browser GPU windows at 1024²
on Chromium / ANGLE Metal / Apple M3 Pro measure 6.00/10.56 ms respectively
(33 samples each). The browser validation overlapped the native capture run;
these timings are diagnostic samples, not isolated or sustained-combat budgets.
Mobile, other native backends, WebGL floating-point HDR and context recovery
remain unqualified.

- `captures/rendering/reflections-verified`: 39 stills across three launches, exact-repeat results and source fingerprints.
- `captures/rendering/reflections-validation`: reflection/glass/shadow diagnostics, toggle returns, a 13-image continuous-history sweep and firing-light checks.
- `captures/rendering/reflections-review-verified`: labelled step-8/step-9 comparisons and `costs.json` with measurement scope.
- `captures/rendering/reflections-browser-verified`: 107 WebGL stages, pixel checks, GPU queries and matching-source build provenance.

## Weapon and combat rendering (step 11)

Weapons, gloves and soldiers share generated combat surface recipes for coated
metal, steel, polymer, woven fabric, camouflage, skin and rubber. Mesh-local or
bind-pose coordinates keep the detail attached during recoil, reloads and skinning.
Physical-frequency brush marks, coating scratches, stipple and weave fade with
pixel footprint; small surface gradients perturb the lighting normal. Metallic
and dielectric responses use the existing world-space daylight, filtered IBL,
room attenuation, local lights and shadows. The carried carbine uses metal and
polymer responses rather than the soldier's fabric response.

The muzzle flash is a feathered emissive quad in the independent weapon depth
pass. It retains coverage through weapon AA and never enters world fog or TAA.
Weapon colour retains RGBA16F on qualified Metal and square-root-encoded RGBA8
on the fallback, now representing premultiplied radiance consistently. A separate
linear flash layer samples the weapon's [texture-backed depth](https://defold.com/ref/render-lua/#render_target) and resolves in a
shader before AA. It reuses idle transparency/AA targets and costs one resolve
draw only while a flash is visible. This preserves dark-tone precision and correct
blending on the compatibility path, with its existing 0–8 radiance ceiling.
World radiance encoding is unchanged.
Sparks and tracers emit light; cartridge cases use a brass response.

Actual firing and impact events feed 24 smoke/world-flash slots and 32 static
impact-mark slots. All 56 meshes share one generated six-vertex buffer (144 bytes
of vertex data). Spawns reuse expired slots or replace the oldest; smoke grows,
rises and fades, and marks fade over the last two seconds of an 18-second life.
Player smoke resolves the animated muzzle rather than spawning at the ballistic
eye origin. Flesh, glass, water and moving fabric/foliage do not receive static
marks. Existing rigid chips, tracers and cases keep their separate 24-slot pool.
Restart clears both pools; pause freezes their lifetimes.

Smoke uses opaque view depth to soften intersections and suppress near-camera
rectangles. Impact marks align to the collision normal and clip against the
receiver's depth and geometric normal, preventing marks across openings or sharp
corners. Glass, smoke, world flashes and decals share a single back-to-front draw
queue with premultiplied linear blending after world TAA. Transparent effects
therefore do not leave temporal trails. This is object-centre sorting of small
quads and nonintersecting panes, not order-independent volume transparency.

The pause menu's **Combat** tab exposes material detail, effects, soft intersections
and impact marks. Automation accepts `combat_materials`, `combat_effects`,
`soft_particles` and `impact_decals` in `renderer.configure`; `combat_fx.snapshot`
reports live counts, events and fixed resources. Version 11 captures add hip/ADS
for all three weapons, indoor weapon lighting, firing, soft intersections and
glass overlap. `capture.shot` optionally accepts `actors=true` to retain frozen
live soldiers while hiding the HUD; ordinary catalogue shots still hide actors.
The mesh component ceiling is 384 to accommodate effects alongside the material
laboratory. No additional render targets or material textures are allocated;
steady 720p HDR target storage remains 218.11 MiB (23 targets).

Validation covers 172 Lua checks, native material/effect toggle returns, actual
shot and impact events, pause/restart/resource bounds, skinned soldier materials,
odd resizing and a continuous camera sweep. All 56 catalogue views match every
RGB pixel across three independent Metal launches. Chromium WebGL 2 passes all
143 capture stages and the full texture/depth/feature/return-pixel assertions.
Native renderer, HDR, temporal, weapons, AI and UI regressions pass. Review artifacts are:

- `captures/rendering/combat-final`: repeatability, stills and frozen native profiles.
- `captures/rendering/combat-validation`: pixel gates, motion samples and live firing costs.
- `captures/rendering/combat-review`: labelled step-10/step-11 comparisons and `costs.json`.
- `captures/rendering/combat-browser-final`: WebGL compatibility captures and GPU samples.

The frozen native weapon view submits 776 draws; its firing counterpart submits
778 (one flash quad and one resolve). These are scene-specific submitted counts,
not a sustained gameplay or GPU benchmark. Physical mobile, other native backends, WebGL floating-point HDR, context recovery
and sustained combat GPU budgets remain unqualified. Geometry bevels, richer
soldier anatomy and source weapon silhouettes remain separate visual-parity work.

## Photographic treatment (rendering step 12)

**Escape → Photo** controls photographic quality, automatic exposure, bloom
strength, colour grade, sharpening, motion blur, ADS depth of field, vignette and
grain. Display's exposure slider remains a manual multiplier (0.25–4) on the
metered value. These settings affect presentation only and never use gameplay RNG.

Bloom now extracts the premultiplied world/weapon composition in exposure-scaled
linear light, including muzzle flashes. A 1.6 threshold with a 0.9 soft knee,
first-level luminance weighting, and a quarter-resolution downsample/upsample
pyramid spread bright light at several scales. Reconstruction averages levels
rather than adding energy at every mip. Default bloom strength is 0.14.

A 64² centre-weighted log-luminance meter reduces through 16², 4² and 1² on the
GPU, without readback. Bright sky receives less weight and individual samples
are clamped to stop flashes/sun glints dominating the meter. Two packed RGBA8
1² targets adapt in exposure stops at 1.4/s toward brighter exposure and 3.2/s
toward darker exposure. The multiplier stays within 0.65–1.8 in daylight/sunset
and 0.8–1.3 at night; the exposure key is 0.18. Pause freezes adaptation, stalls
contribute at most 0.1 seconds, and history resets invalidate the previous meter.

The reference's 33³ colour grade is generated into a 1089 × 33 RGBA8 LUT and
sampled as two bilinear blue slices. It applies slope/offset/power, cool shadows,
warm highlights, saturation, highlight desaturation, contrast and normalized
shoulder/toe **after** the one sRGB display conversion. Luminance-only sharpening
(default 0.25) operates before exposure and is bounded by neighbourhood luminance
and a 0.8–1.2 gain; it requires TAA. The 0.18 vignette attenuates linear light.
Default monochrome grain is 0.006 in display space, reduced in shadows, with a
presentation clock that stops on pause. Neither grade nor grain affects diagnostics.

World blur follows temporal resolve and transparent composition, before adding
the weapon. Motion uses the existing camera/rigid/skinned velocity data, removes
projection jitter, normalizes the shutter to 60 Hz and caps displacement. Its
default strength is 0.15 (0 disables it). TAA must be enabled for motion history.
ADS focus reads centre world depth, clamps focus to 3–18 metres, and uses a
maximum 3.3-pixel circle of confusion, scaled by the actual ADS transition.
Near blur is weaker than far blur. Both gathers reject incompatible depths and
screen-edge samples. The viewmodel and sights stay sharp; glass/smoke still use
the opaque depth underneath them. This bounded gather does not spread foreground
bokeh across silhouettes or reconstruct offscreen motion.

Photographic presets are independent of `render.material_quality` (atlas size):

| Preset | Bloom levels / draws | Optical blur | 720p HDR target storage | 1024² WebGL GPU median / p95 |
|---|---|---|---|---|
| Low | 3 / 5 | Disabled; releases both full-resolution targets | 218.51 MiB | 8.52 / 10.30 ms |
| Medium | 4 / 7 | 9 taps; 12-pixel motion cap | 232.60 MiB | 8.38 / 11.73 ms |
| High (default) | 5 / 9 | 13 taps; 16-pixel motion cap | 232.61 MiB | 11.23 / 13.73 ms |

Medium is the measured compromise for retaining both optical effects. Low's
clear benefit here is memory; its median is within measurement variation of
medium. High retains the broadest bloom and densest gathers for visual review.
These are three alternating 350 ms GPU windows per tier (93–97 valid samples),
Chromium / ANGLE Metal / Apple M3 Pro, a stationary camera with live TAA, ADS and exposure, at 1024².
They are not sustained combat measurements or a mobile performance target.
Native 720p render-script medians are 224 / 239.5 / 263.5 µs; they measure CPU
submission, not GPU time. Native target counts are 33 / 37 / 39; high's bake peak
is 255.80 MiB. Estimates include colour/data/depth attachments and exclude driver,
mesh, sound and shader memory. Disabling either blur control releases its target;
preset changes and resizes reuse or release resources without rebaking materials.

`renderer.configure` accepts `photographic_quality="low"|"medium"|"high"`,
`auto_exposure`, `bloom_strength` (0–0.5), `grade_strength` (0–1), `sharpen` (0–0.5),
`motion_blur` / `ads_dof` (0–1), `vignette` (0–0.5) and `grain` (0–0.03).
Diagnostic `view="bloom"` shows the reconstructed pyramid; `bloom_level=1..5`
selects a downsample level (0 restores reconstruction, levels clamp to the tier).
`view="exposure"` shows current and target log exposure in red/green, mapped from
−2..2 stops into 0..1. `view="grade"` displays the generated LUT.
`renderer.snapshot` reports pass counts, target bytes, quality, exposure limits,
ADS amount and the active exposure mode.

Capture catalogue version 12 explicitly locks exposure and grain phase for
repeatable stills. If auto exposure is enabled during a frozen capture, each frame
uses the instantaneous meter deterministically; `temporal_live=true` instead
permits normal adaptation. Capture end restores the user's settings. Source
fingerprints, pixel checks and costs are saved in:

- `captures/rendering/photographic-validation`: native feature returns, bloom scales, exposure bounds, resize, preset and pause checks.
- `captures/rendering/photographic-adaptation`: live street/sky exposure lag and settling in both directions, pause and Photo menu controls.
- `captures/rendering/photographic-browser`: 28 WebGL stages, exact street return, pixel assertions, GPU samples and build provenance.
- `captures/rendering/photographic-review`: labelled before/after and adapted Three.js comparisons, plus `costs.json`.
- `captures/rendering/photographic-final`: complete native still/motion catalogue and independent-launch repeatability.

Run the two photographic smoke suites above; build a debug HTML5 bundle with
`--settings tests/photographic_browser.project` for the focused browser fixture.
Use `tools/validate_rendering_browser.mjs` as described above, followed by
`python3 tests/photographic_browser_pixels.py`. There are 177 passing Lua checks.
All 56 stills match every RGB pixel across two independent Metal launches; all
five 121-frame sweeps complete with frozen simulation and restored settings.
Native HDR probes also pass at three exposures, preserving radiance above 8,
linear filtering/blending, sRGB transfer and the reference AgX curve.
Temporal regression checks pass for exact capture/resize returns, isolated
weapon AA, camera/actor motion, history resets and continuous sweep playback.
Physical mobile, other native backends, WebGL floating-point HDR, forced context
recovery and sustained combat performance remain unqualified. Source geometry,
matched time-of-day lighting and missing Kaigen captures still prevent claiming
complete cross-engine visual parity or the final agreed-performance gate.

## Atmosphere (rendering step 10)

**Escape → Atmosphere** selects **Daylight**, **Sunset** or **Night** and toggles
cloud layers, fog, volumetric integration and shadowed shafts. The existing
Display fog control is the same master switch. Automation accepts
`renderer.configure` with `lighting="daylight"|"sunset"|"night"`, `clouds`,
`fog`, `volumetric_fog` and `fog_shadows`. All are presentation settings; neither
simulation time nor gameplay random streams change.

`game/render/daylight.lua` supplies the shared celestial directions and spectral
key light. A 48-step CPU extinction integral matches the reference Rayleigh/Mie/
ozone medium. A GPU-generated 768 × 384 sky lookup uses 32 view segments and
16 quadratic light-path segments, with an approximate isotropic multiple-scatter
term. The reference's 1.5 km cumulus and 7.8 km cirrus shells supply deterministic
cloud shapes, deck-specific lighting, self-shadowing and haze. Distant cloud detail
fades by distance and projected footprint to avoid undersampled horizon streaks.
The sun has limb darkening; the moon has a geometric terminator, restrained surface
variation and a static star field. Discs are drawn at screen resolution and excluded
from indirect illumination. Night uses the reference's deliberately elevated moon
illumination, rather than literal physical night exposure.

A lighting/cloud change rebuilds the sky and all filtered environment levels in
the same render update, before drawing the world, and invalidates colour history.
Surfaces, soldiers, weapons, glass, sun/moon shadows and fog use that same key.
`environment_updates` counts complete sky/environment rebuilds; material
`bake_jobs`/`bake_draws` retain the earlier atlas-loading counter contract. The sky
adds one draw to initial loading, and a later preset/cloud change submits two
bake draws without regenerating materials. There is no continuous time animation
or cloud drift in this fixed-state increment.

The world fog replaces the earlier per-material height haze. A half-resolution,
40-segment quadratic march integrates wavelength-dependent extinction and
shadowed in-scattering. It uses cheap cascaded-shadow comparisons, blended cascade
boundaries, a dual-lobe scattering phase and two correlated cloud-shadow samples
per ray. The full-resolution composite applies analytic height transmittance and
depth-weighted reconstruction that rejects foreground/background discontinuities.
Fog follows SSR and precedes world temporal AA, reusing its existing history and
reset rules. The weapon stays in its independent clear layer. Thin glass uses an
analytic front-air approximation after world TAA.

`volumetric_fog=false` skips the march but retains analytic distance attenuation;
`fog=false` skips both passes. `fog_shadows=false` isolates occluder influence.
`view="fog_scatter"` and `view="fog_transmittance"` expose the reconstructed
in-scatter and transmittance through the normal display conversion. The laboratory
window is actual mesh geometry: shafts and their mullion/box occlusion come from
the production shadow atlas, not a painted beam or a screen-space opening mask.
The current market's closed upper windows remain closed; existing doorways admit
light according to their real geometry.

The sky, half-size fog and full-size composite add three targets. At 1280 × 720,
medium HDR storage is **218.11 MiB steady / 241.29 MiB during material loading**,
with **23 / 26 targets**, an increase of 11.04 MiB over step 9. The compatibility
path adds 5.52 MiB. Toggling fog skips work but retains its allocations. The sky
bake is synchronous on preset changes; its transition-frame GPU cost is separate
from steady rendering, and is not a smooth time-of-day animation budget.

Validation and review artifacts are under `captures/rendering/atmosphere-*`.
The native atmosphere suite checks all fixed states, exact preset/cloud/fog return,
matching environment updates, shadow influence inside the window fixture, odd-size
reconstruction, a 13-image continuous-history sweep, settings restoration and
resource ownership. Native renderer, HDR, shadows, occlusion, temporal,
reflection, combat and UI suites also pass, including the Atmosphere tab.
The 164 Lua checks include celestial altitudes, spectral
extinction, strict settings, pass ordering and context-rebake scheduling.
The short native Metal street sample submits **767 → 769 draws** with fog off/on;
median render-script CPU is **175 / 169 µs**, with scheduling variance too large
to infer a speedup. These are submission samples, not GPU or sustained-combat
budgets. See `atmosphere-review/costs.json` for measurement scope and provenance.

This is a bounded adaptation of the reference atmosphere, not its full LUT and
multiple-scattering implementation. Cloud detail is lookup-resolution limited;
surface sunlight does not receive moving cloud shadows. Forced browser context
recovery, floating-point WebGL HDR, other native backends and physical mobile
remain separate qualification gates. The local Kaigen engine remains unavailable.

The WebGL 2 encoded compatibility run passes **124 stages**, including all prior
material, shadow/contact, temporal and reflection pixel checks and the new sky,
environment, fog and shaft checks. Exact camera/feature return pixels also pass.
The isolated Chromium / ANGLE Metal / Apple M3 Pro run records separate 350 ms GPU
windows at 1024²: 8.86 ms median with fog and 19.88 ms without (31/29 samples).
The slower, highly variable off window prevents a causal fog-cost conclusion;
these diagnostic windows are retained in the cost report rather than presented
as a speedup. An earlier concurrent browser/native run timed out; its partial
report is retained separately. A native repeatability run was interrupted by an
AVAudioPlayerNode audio-backend exception, recorded beside its incomplete launch. Its fresh retry passed: **all 46 stills
match every RGB pixel across three successful independent launches**.


## Generated audio

The AudioSynth native extension generates 76 mono PCM16 WAV samples at 22,050 Hz
during loading, using the catalog and tuning from `game/audio/synth.lua`. That Lua
module remains the fallback and verification reference. The bank occupies
1,627,520 bytes (about 1.55 MiB), excluding engine
resource overhead and temporary synthesis buffers. The only bundled WAV is a
32-frame silent placeholder required by Defold sound components. Audible samples
are created with [`resource.create_sound_data`](https://defold.com/ref/resource/#resource.create_sound_data)
and released on teardown. No imported recording is used.

The rifle, SMG and pistol combine a pressure transient, swept low body, noisy crack,
tail and delayed mechanical tick, with source-derived profile tuning. Each has
three deterministic variations and dry, room-reflection and low-pass muffled
versions. Twelve surface families supply impact and alternating-footstep samples.
Reload sounds follow the actual magazine/bolt beats, including cancellation;
dry triggers, casing ejection, landing, stance/slide/mantle cloth and player damage
also have cues. Player shots stay centred; enemy shots and impacts use world
positions. Casing audio accompanies ejection, since casings have no physics.

Synthesis advances in 1,024-sample chunks with a soft 2 ms deadline checked between
chunks. Native generation has a 131,072-sample safety cap per update; Lua retains
its 8,192 cap. Final WAV string copying and resource upload are indivisible.
Gameplay waits at the world's final loading phase until the bank is ready.
`audio.snapshot` reports the synthesis backend and measured total/peak loading
work. The matched macOS native runs took 25 ms median total, with a 2.1 ms peak
update. Loading rate and sound variation never affect world generation,
weapon spread or enemy random streams. There is no synthesis during combat.

Twenty-two one-shot slots and two dedicated ambience loops bound playback to 24
voices. Four one-shot slots are reserved for local shots, dry triggers and hurt
cues. A 64-entry presentation queue drops overflow or events older than 150 ms;
slots are reused only after Defold's completion callback, including stopped sounds.
The mixer follows the displayed camera, updates stereo pan and distance gain,
checks Bullet world occlusion when a cue starts, and attenuates blocked sounds.
Blocked gunshots also use the muffled waveform. Shop bounds select the reflected
gunshot variant and reduce the generated wind/city ambience. A conservative sum
of sample peaks limits simultaneous output, with gradual gain recovery.

Encounter restart stops current voices and clears queued cues while retaining the
bank. Focus loss stops playback; focus return starts fresh ambience without
replaying old combat sounds. Master, weapons, foley and ambience gains (0..1), plus
mute, are available through `audio.configure` and the pause menu's Audio tab.
Browser playback starts after the first click on the game canvas.

The ten Lua audio tests verify WAV format/amplitude, deterministic chunking,
spectral muffling, spatial transforms, routing, cancellation, queue/voice limits,
mix headroom, mute/focus/restart cleanup, resource release and RNG isolation.
The native suite checks actual mixer output and stereo channels, real wall
occlusion, room selection, all three weapons, reload/footstep/damage events,
surface playback, enemy fire and six encounter restarts without bank growth.
An HTML5/WebGL 2 smoke check also confirms nonzero Web Audio output after the
first click, movement/enemy combat sounds, encounter restart and reduced room
ambience, without Lua or sound errors. The in-app browser rejected pointer lock,
so player-fired browser shots remain outside that check; native tests cover them.
Mixer peaks describe recent audio buffers and can retain the last value when
the device becomes idle; completion callbacks track live voices separately.
Physical mobile validation remains outstanding. These are compact synthesized
approximations: full source timbre parity, soldier footsteps/voice barks, distant
battle scheduling, continuous occlusion filtering, HRTF and convolution reverb
remain future work. The room treatment uses two early reflections.

## Automation

The debug bridge exposes `gameplay.snapshot` (timing, input intent, health,
physics settings and capsule position/velocity/stance) and `gameplay.damage`
(queue a hit through the combat owner).
It also publishes the `world` state and exposes `world.snapshot`, `world.validate`,
`world.raycast` and `world.view`. Ray hits include the authored collider id and
surface. `world.view` takes `{name = "street"}` or any named inspection view listed above.
`movement.course` creates the optional fixtures; `movement.reset` resets feet
with `{x, y, z, yaw}` and optional `{velocity = {x, y, z}}`. `movement.drive`
accepts `{segments = {{ticks = 120, move_z = -1, sprint = true}, ...}}` with
optional move_x, crouch, prone, aim, jump, jump_held, lean and look_x/look_y.
Lean is -1/0/1. Jump is a press on the segment's first tick and stays held for
that segment; jump_held can continue a held request without another press.
Sprint/crouch edges follow hold transitions; sprint_pressed/crouch_pressed can
also supply explicit first-tick edges. Look values are per-tick pixel deltas. Each drive is
limited to 2,400 ticks. `movement.result` returns completion and immutable final
metrics, including slide/tactical ticks, mantle completion/abort counts, peak
speed and lean, so polling latency does not change the measured endpoint.
`weapons.snapshot` exposes ammo, chamber, mode, clip progress, ADS, spread, recoil
and projectile counters. `weapons.drive` replays up to 64 input segments (at most
2,400 ticks) through ordinary buffered inputs before each fixed tick; booleans
include fire, aim, reload, inspect, fire_mode, next_weapon and weapon_rifle/smg/
pistol. `weapons.result` returns its frozen final snapshot. `weapons.range`
creates optional fixtures at z=23..47 and reports target health; reset the player
to x=-5/0/5, y=0.01, z=40, yaw=0 for bare/wood/concrete lanes.

Discover commands with `game.application_catalog(kind="command")`.

`ui.snapshot` reports pause/focus, live audio/display/sensitivity settings,
compass heading, damage feedback, killfeed and minimap rectangle count.
`ui.pause` takes `{paused=true|false}`. It uses the normal pause transition,
including sound suspension and input cleanup. `ui.configure` changes one live
setting with `{kind="audio"|"renderer"|"input",key="master",value=0.5}`;
the input kind accepts `key="sensitivity"`, in 0.25..3. Pause/resume does not
advance automation drives; they continue with the simulation after resume.

`audio.snapshot` reports loading progress, bank bytes, live/peak voices, event
counts, settings, the latest cue, per-voice gain/pan and native mixer peaks.
`audio.configure` takes any subset of `{master, weapons, foley, ambience, muted}`.
`audio.preview` auditions `{kind="shot", weapon="rifle"|"smg"|"pistol"}` or
`{kind="impact"|"step", surface="wood"}` with an optional world
`position={x,y,z}`. It uses the ordinary bounded queue and spatial mixer without
emitting gameplay events.

`ai.snapshot` reports state, health, travel, shots, mesh/palette sizes and upload
cost. `ai.configure` takes `{enabled=false}` to freeze a shootable soldier.
`ai.reset` replaces it with full health, optionally at `{position={x,y,z},yaw}`,
while preserving that pause setting. `ai.volumes` returns live hit-volume centres.
`ai.route` takes `{target={x,y,z}}` and returns validated waypoints; `ai.patrol`
takes `{points={{x,y,z},...}}` (1–8 points) to exercise normal navigation without
changing the behavior code. `gameplay.restart` performs the same encounter reset
as key 9. Native resources are released on replacement/finalization, and the
shared mesh resource is retained until finalization.

Example:

```python
from automation_bridge import editor

project = editor.open_project(".", start_if_needed=False)
game = project.build_and_run()
print(game.command("gameplay.snapshot", {}))
print(game.command("gameplay.damage", {"target": "player", "amount": 25}))
game.wait_frames(2)
assert game.command("gameplay.snapshot", {})["result"]["health"] == 75
```

Run Python with `PYTHONPATH=automation-bridge-python`. Application commands are
registered only when the Automation Bridge Lua API is available.

Squad automation: `ai.snapshot` returns actors in ID order, squad reports,
cover/flank claims, actor roles, memory, replans and completed flanks. Actors also
report `suppression`, `suppressed`, `suppression_events`, `suppressed_ticks`,
`crouch`, `stance`, `cover_phase`, `peek_timer` and `peeks`.
`ai.reset` with no position restores all six; an explicit `position` retains the
single-soldier fixture used by weapon/navigation suites. `ai.route` and `ai.patrol`
accept an optional actor `id`. `ai.volumes` includes each volume's actor ID.
`ai.configure` accepts `enabled` and a diagnostic `damage_scale` in 0..1; zero
preserves physical bullets/impacts while suppressing their health damage for
sustained profiles. Normal encounter restart restores the scale to 1.
`ai.validate_suppression` starts the opt-in shared integration scenario;
`ai.suppression_result` returns its phase and recorded assertions. The scenario
resets the encounter and freezes AI after success; use `gameplay.restart` to
return to ordinary play.
