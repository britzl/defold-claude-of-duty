# Defold port implementation plan

Created: 2026-10-13. Updated: 2026-10-23. Target engine: Defold 1.14.0.

Implement a runtime-generated Defold port of Claude of Duty, with Lua gameplay systems and a custom render pipeline. Introduce a portable native extension only where measured geometry, animation or audio requirements justify it. The current acceptance platforms are Mac native and desktop browser, targeting 60 FPS (user decision, 2026-10-15). Keep input and graphics adaptable; physical mobile qualification is deferred outside the current gate.

The target is feature and presentation parity with the local Three.js and Kaigen versions: the recognizable market street, procedural soldiers, three weapons, movement, combat, audio and interface. Preserve runtime generation wherever practical rather than making pre-baked art and audio the default. Equivalent behavior and appearance matter; engine-specific implementations do not have to be copied.

**Playable Kaigen reference:** [Claude of Duty — hosted HTML5 build](https://kaigen3d.com/demos/claude-of-duty/). The user confirmed its availability on 2026-10-23. Use this build for hands-on gameplay, visual and audio reference. See [Kaigen availability](parity/README.md#kaigen-availability) for source provenance and controlled-capture status.

**Visual follow-up (2026-10-23):** The [three-version visual review](parity/README.md#visual-review--2026-10-23) records gaps in interior illumination, weapons/hands, materials, prop variety, foliage, default sky/lighting and interface styling. All follow-up implementations are now present: separate diffuse room fill and bounded reflected lamp light; smoother, darker weapons and shaped gloves/sleeves; finer road/wall materials; varied market goods and sagging awnings; fuller palms; broken clouds; and compact translucent HUD/menu styling. Near-camera material parameters also upload correctly. See [current implementation, checks and resource counts](README.md#materials-market-and-interface-refinement-2026-10-23). Native and browser checks cover rendering, UI and geometry, with unchanged navigation/collision. Exact reference appearance, motion/effect parity and sustained performance remain separate qualification work.

## Current status and scope

The 2026-10-15 source audit used Defold revision `8146e12` and the two local reference archives. The subsequent step-1 increment adds the [versioned parity contract and source lock](parity/README.md), reference capture fixes and shared laboratory geometry. Step 2 expands the market to its full reference extent and footprints. Step 3 adds the four remaining surface families and shared foliage coverage; step 4 implements detailed architecture and dressing. Step 5 implements vaulting and the reference camera motion families. Step 6 adds player regeneration, fall damage, suppression and low-health feedback. Step 7 adds detailed weapon assemblies, shared articulated arms, hand tracks and fixed-tick first-person motion. Step 8 reconciles penetration loss/deflection and animated regional damage. Step 9 adds three soldier variants, layered animation, planted foot/hand IK and ragdoll joint frames. Step 10 adds bounded native Bullet debris, constrained ragdolls, regional/blast impulses, sleep and cleanup. Step 11 adds evidence-based hearing/search, wounded retreat, magazine/burst/reload cycles, tall-cover peeks, squad permissions, general flank/reposition choices and swept low-obstacle vaulting. Step 12 adds squad-rationed animated enemy throws, reserved Bullet grenades, fixed-tick fuses, obstruction-aware blasts and connected warning/FX/audio. Step 13 adds twelve surface-effect recipes, ballistic fragments, receiver-tested blood/scorch decals, layered explosions, movement/death dust, persistent wreck smoke, motes and depth-tested heat refraction; validation is recorded below. Step 14 adds continuous solar time, drifting clouds, shared cloud shadows, animated fog and staged/blended sky-environment updates. Step 15 adds combat/voice/UI audio, contact-driven casing/body sounds, continuous layered filtering/reverberation, bus ducking and concussion; full HRTF/convolution and listening acceptance remain open. Step 16 adds floor-aware enemy minimap contacts, live projected grenade/fuse warnings, damage numbers, elimination banners, continuous damage bearings, magazine/reload feedback and optional objective/prompt displays. Step 17 completes desktop/gamepad adapters, simplified touch gestures/layouts, input settings and browser activation handling. Step 18 adds whole-game presets, Auto quality and release workload measurement tools; full performance qualification remains open. Historical rendering counts remain prior results. Cross-engine sustained performance comparisons have not been established. The hosted Kaigen demo runs, but the local archive lacks its engine and the published build/source relationship and controlled capture adapter remain unverified.

**Status convention:** `[x]` means the stated implementation is complete in the current port; `[ ]` means work remains. Implementation completion does not imply full source fidelity, all-platform qualification or an agreed performance budget. The ordered backlog below is the current execution plan; the historical record at the end preserves earlier design and validation details.

### Already implemented

- [x] Gameplay framework: seven subsystem modules, 120 Hz fixed simulation, buffered input, independent random streams, gameplay events, centralized damage and interpolated presentation.
- [x] Generated full market layout: 104-metre road, all 20 reference footprints, five flank routes, far cross street, ruin yard and gate passage; connected W2/E1/E2 floors, ground-only E3, shared collision/navigation/cover/room metadata and a full-map minimap. Step 4 adds source-derived architecture, furnished rooms and street dressing.
- [x] Core traversal: swept capsule, walking/sprinting/tactical sprint, jump buffering/coyote time, crouch/prone, steps/slopes, sliding, clearance-checked mantling/vaulting, collision-limited leaning and a fixed-tick camera rig.
- [x] Core weapons: M4A1/MPX-9/P-19, fire modes, magazine/chamber state, reload/inspection/switching timelines, ADS, recoil, spread, projectile travel/drop and material penetration; generated weapon assemblies and articulated arm/hand IK in an independent render pass.
- [x] Core soldiers/combat: three generated 25-bone soldier variants, terrain/hand IK, layered animation, animated hit volumes, patrol/detection/pursuit/fire/death, two squads of three, shared alerts, cover claims, low-cover peeking, suppression, friendly firing-lane checks and a west-loop flank.
- [x] Core audio: 234 generated dry/muffled/wet samples, budgeted loading, bounded spatial mixer, player/weapon/surface cues, ambience, initial occlusion and room variants, volume controls and lifecycle cleanup.
- [x] Core desktop UI: crosshair/hitmarkers, ammo/mode, health/basic damage direction, compass, geometry minimap, killfeed, pause/settings, focus handling and encounter restart.
- [x] Rendering/capture infrastructure: the stages listed below, deterministic capture manifests, still/motion fixtures, a material laboratory and a Three.js capture adapter.

### Rendering implementation status

These are the original rendering-stage numbers, not the remaining implementation order.

| Stage | Completed implementation | Remaining scope |
| --- | --- | --- |
| 1. Comparisons | Capture catalogue, laboratory, deterministic stills/sweeps, source lock, 24-scenario contract and Three.js shared-geometry adapter | Controlled Kaigen captures, six Three.js special/transient fixtures, reference motion and fully matched scenes |
| 2. HDR/colour | Metal RGBA16F, linear lighting, sRGB conversion, AgX and encoded RGBA8 fallback | Floating-point HDR qualification on WebGL and other target backends |
| 3. Surface recipes | All nineteen reference families, generated maps, mip isolation/filtering, three material tiers and shared foliage coverage | Assignment on detailed step-4 geometry and matched reference appearance |
| 4. Weathering | Deterministic variation, wear/grime masks, microdetail and selective parallax | Assignment and tuning on the completed geometry |
| 5. Lighting | Unified sun/sky, filtered environment response, interior attenuation and room lights | Matched reference lighting throughout the full map |
| 6. Sun shadows | Four stabilized cascades, contact-hardening filtering and animated/cutout casters | Full-map quality/cost tuning and platform qualification |
| 7. Contact depth | Shared prepass, GTAO-style occlusion and contact shadows | Reference appearance/stability and device qualification |
| 8. Temporal stability | Camera/object/skinned motion, world TAA, history resets and separate weapon AA | Full-content motion regression and device qualification |
| 9. Reflections/lights | SSR with environment fallback, thin glass, local-light selection/shadows and muzzle lighting | Full-map tuning and backend/cost qualification |
| 10. Atmosphere | Fixed and animated solar time, drifting cloud layers and shadows, celestial bodies, volumetric fog/shafts and staged environment updates | Exact reference lighting/radiometry and sustained cost qualification |
| 11. Combat rendering | Weapon/soldier material detail, emissive flashes, soft smoke/dust and impact marks | Detailed models and the complete reference effects catalogue |
| 12. Photography | Multiscale bloom, exposure adaptation, grade, sharpening, motion blur, ADS depth of field, vignette and grain | Final visual parity and sustained/device performance gates |

Do not reimplement these rendering stages as missing features. Extend their documented limits and qualify them as the remaining content arrives. The latest recorded photographic increment reports 177 Lua checks, exact repeats of 56 native stills across two launches, five 121-frame sweeps and a focused 28-stage WebGL fixture. These results do not establish full browser gameplay coverage, mobile support or cross-engine parity.

## Remaining work in implementation order

Start with reference setup, then build the shared content and simulation dependencies before their presentation layers. Keep native and browser smoke checks, resource accounting and comparison captures running after each relevant increment. Steps 18–19 close performance and platform qualification; they are not reasons to postpone all profiling or device checks until the end. Missing Kaigen access blocks its comparison gate, not independent implementation work.

### 1. Establish the parity baseline and acceptance targets — PARTIAL

- [x] Defold capture/test harness and adapted Three.js reference capture path.
- [x] Versioned 24-scenario comparison matrix with source references, expected behavior, verification procedures and existing coverage in `parity/contract.json`.
- [x] Lock local runtime source hashes and all 71 production cameras/FOVs, seeds, level transforms, solar hours and quality/exposure policies. Exact reference Git revisions are unavailable for the source archives; no commit identity is guessed.
- [x] Fix Three.js per-shot weapon/time/clear-sky state, record actual exposure/camera/GPU settings, import production laboratory triangles and validate repeat pixels from fresh pages. Pending/failed/omitted evidence is kept distinct.
- [x] Verify the published Kaigen demo renders and record its build ID separately from the local source archive; mark controlled capture and performance evidence unavailable.
- [x] Set Mac native and desktop browser to 60 FPS. Record proposed 1280×720 loading, resident-memory, CPU/GPU and p95/p99 frame budgets plus a sustained release-run protocol; these are targets, not measured passes. Mobile qualification is outside the current gate.
- [x] Record eleven adaptation decisions, including eye-origin firing, map layout, damage scales, controls, coordinates, exposure and audio. Open decisions remain assigned to their acceptance scenarios.
- [ ] Add controlled Kaigen captures and its equivalent laboratory once a matching runnable build/engine and capture control are available.
- [ ] Complete Three.js cutout/local-light/glass and foliage fixture qualification, transient firing/FX timelines and reference motion sweeps. Twelve catalogue stills (six original and six new foliage views) are explicitly pending rather than represented by unrelated source shots.

**Completion check:** The versioned comparison matrix and baseline workflow are implemented. Controlled Kaigen and the listed reference-fixture comparisons remain open; this is not a full parity claim. Continue independent implementation with step 2 while closing those reference gates.

**2026-10-15 validation:** 15 focused Node/Python/Lua checks passed, plus source-lock acceptance/rejection checks. All 50 supported Three.js shots have exact repeat pixels across the recorded initial/recovery runs; six stills are explicitly pending. A late browser-load timeout is preserved in the evidence, and the remaining four pairs passed across eight fresh browser launches after browser-lifetime bounding was added. Existing native capture source/image hashes were rechecked; the native suite was not rerun. See `parity/README.md` for commands and limits.

### 2. Complete the full market layout and navigation — COMPLETE

- [x] Full z=-58..46 street and all 20 source building footprints/storey counts: W1–W5, E1–E5 and ten background buildings, with the eastern flank, remaining alleys, ruin yard, cross street and gate footprint.
- [x] Shared structural descriptions for entrances, five stair flights, floor connections, occluding masses, eight reference spawn anchors, six enemy spawn/patrol positions and ten cover candidates. E1 has street and alley entrances; E3 has no invented upper-floor link.
- [x] Five connected flank routes, a clear gate passage and a street-spine detour around BS3. Open infill ground-floor passages preserve the existing west loop.
- [x] Full terrain and visible outer boundaries replace excerpt-only yard walls. All 543 collider rectangles reach the minimap; a 256-node visible pool avoids truncation. Room audio, twenty light records and eight indirect-light volumes use the same building layout, with bounded HTML5 lighting messages.
- [x] Extend engine resource limits and bounded loading for the full map; paginate debug navigation to respect the bridge response limit.
- [x] Native traversal/patrols and desktop-browser physics/route validation, including pixel checks for the pooled minimap.

**Completion check:** A full-map traversal and six-actor route matrix reaches every intended floor and route without unsupported navigation links, blocked entrances or collision/visual mismatches. Detailed dressing follows in step 4. E2's retained extra interior, simple infill arcades, flat terrain/boundary walls and the rectangular structural gate opening are recorded adaptations; exact architectural openings, ruins and pointed arch belong to step 4.

**2026-10-15 validation:** All 181 Lua checks passed, plus the 12 baseline-tool Node/Python checks and eight browser minimap pixel checks. Mac Bullet confirmed all 543 collider dimensions (maximum error < 0.000003 m), all 189 supported nodes and both directions of all 194 capsule-swept links. All six spawn actors reached 13 route destinations in the route matrix (78 queries) on native and Chromium WebGL2/ANGLE Metal. Native player traversal completed five flank circuits, all five stair flights, E1's alley entrance, E3's room and the gate/south gap in both directions, without jumps, resets within a circuit or recovery failures. Live AI climbed both E1 flights and returned, then completed the eastern circuit. Eight inspection views were captured on each backend. A fresh native quick run verified the final HTML5-safe lighting transport and GUI layer fix; both engines shut down without runtime errors. Reports/images are under `build/full-market-validation`, `build/full-market-quick-validation` and `build/full-market-browser-validation`.

The previous excerpt capture receipts remain in `parity/excerpt-baseline-v1.json`; the refreshed source lock carries no stale visual evidence. The full-map screenshots above validate this increment, not cross-engine visual parity.

**Resource account:** 1,983 generated boxes, 362 mesh batches, 543 colliders, 148,596 vertices (10,698,912 bytes), 189 navigation nodes and 194 edges. The full-map scan peaks at 145 visible minimap rectangles. Sustained 60 FPS qualification remains steps 18–19; these resource counts and layout smoke checks do not establish it.

### 3. Complete the reference material catalogue — COMPLETE

- [x] Nineteen surface families plus microdetail, generated during bounded loading, with stable IDs and three material tiers.
- [x] Add sand, corrugated metal, burlap and foliage using reference recipes, physical tile scales, relief, roughness and weathering. Hessian uses the reference world-palette tint/0.16 m weave scale and separate 0.5 m normal bake scale.
- [x] Connect foliage cutouts to colour, camera depth/motion, sun and local shadows through the shared filtered coverage path. Two-sided cards retain a common UV orientation; leaf height is independent of coverage and distant ordered coverage avoids disappearing leaves.
- [x] Extend close-up, distance, grazing-angle, back-face, shadow and motion fixtures. Catalogue v13 contains 71 cameras; the laboratory has 35 batches and 31,926 vertices.
- [x] Apply sand to outer terrain and its physics/audio surface. Retain the full-map geometry/navigation and raise the mesh pool to 640 for the full map, actors, effects and laboratory.

**Completion check:** The catalogue is generated at runtime with isolated mip borders and repeatable coverage in all geometry passes. The four materials remain distinct at the tested distances and tiers. World dressing is step 4; reference visual matching and sustained performance remain steps 18–19. Six new Three.js foliage fixtures are explicitly pending, alongside the six earlier reference fixtures.

**Resource account:** Low/medium/high atlas sizes are 1024×1650, 2048×3282 and 4096×6546, holding 174/194/214 mip regions. The three resident RGBA8 maps occupy 19.34/76.92/306.84 MiB; bake draws are 1547/1727/1907. World batches rise from 362 to 374 because sand is separate from dirt; geometry stays at 1,983 boxes, 543 colliders and 148,596 vertices (10,698,912 bytes). No render targets were added. These allocations are not measured process/GPU residency or a performance pass.

**2026-10-15 validation:** 183 Lua checks and 12 Node/Python baseline-tool checks passed. Native Metal passed all three atlas tiers (174/194/214 mip regions per map), leaf-mask mip energy, 45 exact still repeats, front/back leaf coverage, matching depth/normal occupancy, sun/local shadow toggles and exact restores. Four medium-tier 121-frame sweeps retained temporal history without resets. Chromium WebGL2 / ANGLE Metal passed the focused 62-stage medium-tier fixture and its map/coverage/depth/shadow/motion pixel gates. All test engines closed without runtime errors. A fresh native full-market quick run confirmed 543 collider dimensions, all 189 supported nodes, all 194 links in both directions, 78 six-actor route queries and eight inspection views. Full player circuits were not rerun because geometry/navigation did not change. Reports are in `build/material-catalogue-validation`, `build/material-catalogue-browser-validation` and `build/full-market-quick-validation`.

### 4. Complete building recipes, interiors and dressing — IMPLEMENTED

- [x] Reusable shop/apartment recipes, stairs, furnishings, stalls/crates and closed façades.
- [x] W1/W2/W4/W5 setbacks, terraces, balconies, arched trim, recessed windows, bevels, chipped render, W3/E3 broken floors and roof details; pointed gate with rampart, corbels, merlons and stepped gatehouses.
- [x] E1 shop/storage and E3 ruin/storage programmes, stocked shelves, rugs, wall/ceiling furnishings and seven additional room navigation nodes. W2 gains its source setback with adjusted furniture and hall openings; E2 retains its documented three-floor adaptation.
- [x] All authored dressing families: eight stalls, barriers, course-laid sandbags, three wrecks, seven palms, five lamps, cables, laundry, rugs, rubble, tyres and small props. Geometric palm leaflets retain connected silhouettes at distance.
- [x] Material assignments, simple collision envelopes, 25 cover candidates, navigation/minimap metadata, tight mesh bounds, bounded loading and independent decorative streams. Compatible surface families batch together; hidden batches never reach buffer upload.

**Implementation check:** The content recipes and traversal checks are implemented. Matched street/interior/courtyard captures document the result. W2/E2 room adaptations, route-safe prop shifts, reduced tessellation and simplified collision are explicit; exact cross-engine content density, lighting and visual acceptance remain part of step 18. This is not a claim of pixel or sustained-performance parity.

**2026-10-15 validation:** 185 Lua checks and 12 Node/Python baseline-tool checks passed. Native player traversal completed all five flank circuits, all five stair flights, E1's alley entrance, E3's entrance, all five added room routes and the gate/south gap in both directions (16 sequences), plus live E1/eastern AI patrols. Final native and WebGL checks validated 196 supported nodes, 201 capsule-clear bidirectional links and 108 six-actor route queries. Eight inspection captures and eight browser minimap pixel gates passed. The full walk preceded the final stall/frond refinements; the final collision changes were rechecked by both native and WebGL capsule/route matrices. Four native comparison stills repeat exactly; three matching Three.js camera captures were inspected. All owned engines/browsers shut down cleanly.

**Resource account:** 4,450 shapes, 478 batches, 1,224 colliders, 409,386 vertices and 29,475,792 vertex-stream bytes (28.1 MiB). The final native load accumulated 1,430.944 ms of work with a 13.489 ms peak update. Frozen street/interior/courtyard/detail views submitted 3,379 / 3,264 / 2,762 / 2,370 draws across all passes (16–17 profiler samples per request). Full records are in the README and `build/world-detail-native-validation/manifest.json`. Physics and traversal receipts are in `build/full-market-validation`, `build/full-market-quick-validation` and `build/world-detail-browser-final`; matched reference images are in `build/world-detail-threejs-validation`. No render targets or atlas tiers were added. The implementation keeps the 2 ms work deadline, permits 48 geometry jobs and at most eight uploads per update, and reserves 640 meshes / 1,280 collision objects / 2,048 collection instances. Individual jobs can exceed that deadline; measured peaks are retained.

### 5. Complete traversal and camera feel — IMPLEMENTED

- [x] Core movement, tactical sprint, slide, mantle and lean.
- [x] Add proactive vaulting over thin obstacles with verified landing clearance, distinct from climbing onto deep ledges.
- [x] Add stride/footfall camera motion, landing dip/pitch/roll, strafe/turn banking, breathing and reference slide/mantle camera offsets.
- [x] Match sprint/ADS FOV transitions and provide camera impulse channels for damage, suppression and explosions.

**Implementation check:** Thin obstacles and deep ledges have distinct endpoints; all paths and landing clearance are checked before committing and rechecked during traversal. Camera bob follows actual footfall distance; landing, banking, breathing, slide/mantle/vault motion and FOV use reference tuning. The composed eye/aim is shared with firing and collision-limited after interpolation. Damage hooks and bounded suppression/explosion camera channels are present; step 6 connects suppression detection/feedback, while grenade damage remains step 12.

**Adaptations:** Preserve per-tick swept up/across/down traversal rather than the references' unchecked rooted curve; require Jump for deep ledges. Springs use analytic integration, shake uses deterministic sine components, and the mantle pitch settles before completion. Controlled cross-engine motion review and sustained performance remain steps 18–19.

**2026-10-17 validation:** All 244 standalone checks across 27 suites passed, including vault rejection/interruption, camera pose equivalence at 30/60/144 presentation FPS, bounded impulses, firing alignment and pause/death/reset handling. The shared 13-scenario fixture passed on Mac Metal and Chrome WebGL2 / ANGLE Metal (release engine), including real Bullet vault/mantle paths, dynamic obstruction, pause/resume and applied camera FOV. Native and Wasm fixed-input traversal counters match, with endpoint differences below 0.03 mm. The existing native movement and feature suites also passed. Full-market regression passed all 16 player routes in both directions, 108 six-actor route queries, both E1 AI stair flights, the eastern AI circuit and eight inspection captures, with clean shutdown. The fixtures are implementation evidence, not controlled reference motion or sustained-performance qualification. Reports are in `build/traversal-unit-validation`, `build/traversal-native-validation` and `build/traversal-browser-validation`.

### 6. Complete player health and suppression — IMPLEMENTED

- [x] Centralized damage/death, health display, hit flash and basic damage direction.
- [x] Add delayed, ramped regeneration and fall damage through the existing health owner.
- [x] Add near-miss/hit/explosion suppression and directional camera impulses using step 5's channels.
- [x] Add low-health pulse/desaturation and recovery state for the HUD/audio work; ensure death, pause and restart reset or freeze it correctly.

**Implementation check:** Combat owns the 4.6 s recovery delay, 0.55 s ramp to 34 HP/s and landing damage above 15 m/s at 7 HP per additional m/s. Real hostile projectile segments/impacts feed a bounded suppression pool with visibility checks and per-round maximum contributions, including hits. Shot origins drive camera/HUD direction. Low health provides smoothed desaturation, a double heartbeat pulse, hit flash and HUD recovery state. Pause/loading/inspection freeze progression; death stops recovery/heartbeat/suppression and freezes the death treatment; encounter restart clears all feedback.

**Adaptations and remaining scope:** Suppression uses actual travelled projectile segments and explicit ownership instead of the reference impact-direction heuristic. Visibility rays start at the clear eye so endpoints inside solid cover cannot leak suppression. Explosion events supply feedback only; the future grenade owner applies obstruction-aware blast damage once (step 12). The existing composite applies the health treatment in exposed linear HDR before AgX and after temporal resolve, without extra render targets/passes or exposure-meter feedback. Heartbeat/health events are ready for step 15 audio; no heartbeat sound was added. Controlled reference visual comparison remains step 19.

**2026-10-19 validation:** All 257 standalone Lua checks across 28 suites passed, plus 12 baseline-tool checks. The shared 13-scenario fixture passed on Mac Metal and Chrome WebGL2 / ANGLE Metal (release Wasm engine), using real Bullet falls, stopped rounds, near misses and player hits. It covers delayed/ramped/interrupted/full recovery, pause, death and restart. Three captures per backend show healthy, low-health and recovered states; three pixel gates per backend verify colour loss/restoration. Reports are in `build/health-unit-validation`, `build/health-native-validation` and `build/health-browser-validation`. No render targets, draw passes, atlas allocations or audio samples were added; sustained performance and cross-engine parity are not established by these fixtures.

### 7. Complete weapons and first-person animation — IMPLEMENTED

- [x] Three weapon definitions, fire control, ammunition/chamber logic, ADS/recoil and procedural clip timelines.
- [x] Source-scale silhouettes and attachment/grip frames, open handguards, stocks, optics, slide details and separate magazine/bolt/charging/trigger/selector assemblies; generated sleeves, gloves and articulated fingers.
- [x] Body-fixed shoulders and two-bone arm/hand IK, camera-follow springs, layered idle sway, footfall-distance bob, landing response and support-hand reload/inspection/draw/holster tracks.
- [x] Rotation-aware ADS and collimated dots, unchanged ammo-transfer/interruption rules, pause/death/reset handling and the existing indoor lighting and independent viewmodel render/AA path.

**Implementation check:** All three weapons have hip/ADS/fire/reload/charge/inspect captures and production ammunition/interruption scenarios on native and release WebGL. Hands follow grip, magazine and charging targets; sleeves remain connected to fixed shoulders. Fixed-tick presentation and sampled joint matrices agree at 30/60/144 FPS. Switching after empty-mag transfer still permits chambering with no reserve. Firing cancels inspection immediately while a short outgoing-pose blend avoids a visual snap.

**Adaptations and remaining qualification:** The models use fewer procedural primitives than the reference and retain visibly reduced surface/silhouette detail. Finger curls use source-derived poses; the arm solve allows bounded sleeve length correction on extreme reload reaches (1.162× maximum in the sampled clip matrix) to preserve wrist connection. Sine layers replace reference noise; actual footfall distance drives bob, and full ADS constrains the sight/dot to the authoritative camera axis. Seven matching Three.js still requests support review, but exact material/detail matching, reference motion and controlled Kaigen comparison remain steps 18–19. This implementation status is not visual-parity acceptance.

**Original step-7 resource account:** 19,446 weapon vertices across 24 assemblies plus two shared 7,548-vertex arm meshes: 1,442,064 vertex-stream bytes before engine overhead. Seventeen matrices per arm are uploaded in two palette calls. The existing adapter grows from 48 to 50 objects/buffers, including its unchanged 24 effect slots; the active viewmodel adds two draw calls. No new render targets, atlas resources or native extensions. The [2026-10-23 refinement](README.md#weapons-and-hands-visual-refinement-2026-10-23) records the current, higher geometry counts.

**2026-10-19 validation:** 268 standalone Lua checks across 29 suites passed. The shared native/Chromium WebGL2–ANGLE Metal release fixture passes 19 checks and captures 19 poses per backend, covering all weapons, pause and interrupted empty reloads. Seven native frozen views repeat exactly; arm materials, indoor lighting and weapon AA pass three pixel-change/exact-return gates. The 12 baseline-tool checks also pass. Evidence and reproducible commands are in the README and `build/viewmodel-*`. These are implementation/resource checks, not sustained performance qualification.

### 8. Reconcile ballistics and regional damage — IMPLEMENTED

- [x] Full-segment projectile queries, travel/drop, measured penetration thickness and per-round damage deduplication.
- [x] Deterministic material exit deflection using private round streams and the twelve reference scatter coefficients; re-query remaining flight after each bend.
- [x] Four articulated arm volumes and reference regional scales: head 4×, chest 1×, lower torso .9×, arms .65× and legs .7×. Preserve region/part through damage and death events.
- [x] Reference linear penetration loss against each layer's remaining entry budget, unchanged weapon/range tuning, and an explicit eye-origin muzzle-obstruction rule.

**Implementation check:** All eleven soldier volumes are checked in three animated poses through actual native/release-WebGL Bullet queries. The query path refreshes broadphase bounds immediately after skeleton transforms, fixing misses on recently moved limbs. First contact selects the actor's damage region once per round. Six material lanes exercise thin/thick, layered, overlapping and starting-inside geometry; production firing checks blocked and clear eye rays, pause freezes flight, and three encounter resets retain bounded resources.

**Adaptations and remaining qualification:** Collision-limited eye-origin firing is retained. Cover on the aim ray is hit even when the separately rendered muzzle protrudes through it; muzzle-only overlap does not block a clear eye ray. No muzzle teleport or render-pose-dependent collision is introduced. Measured oriented boxes replace reference capsule/sheet proxies; arm boxes split at elbows. Loss accumulates over actual travel across ticks, with overlapping solids consuming power together and each retaining its entry budget. Deflection occurs on exit, with no unqueried epsilon jump. Quadratic range falloff uses cumulative travelled distance and is applied once. Gaussian scattering uses independent Park–Miller streams rather than reproducing the reference RNG's exact samples. Enemy weapon tuning remains step 11; full visual/reference and sustained-cost acceptance remain steps 18–19.

**Resource account:** Eleven volumes per soldier (66 across six actors), up from seven (42). This adds 24 collision objects, taking the soldier adapter from 54 to 78 objects; mesh/buffer, palette, render-target and draw counts are unchanged. Projectile limits remain 128 per subsystem and six material entries per round. Immediate Bullet queries refresh bounds; their sustained-combat cost remains to be profiled.

**2026-10-19 validation:** All 282 standalone Lua checks across 30 suites and the 12 baseline-tool checks passed. The shared eight-check fixture passed on Mac Metal and release Chrome WebGL2/ANGLE Metal, including 33 posed native-volume checks and three reset cycles. Reports are in `build/ballistics-unit-validation`, `build/ballistics-native-validation` and `build/ballistics-browser-validation`. The existing 13-check native health fixture and updated native soldier combat/navigation/replacement suite also pass. These implementation checks do not establish controlled cross-engine or sustained-performance parity.

### 9. Complete soldier variants and animation — IMPLEMENTED

- [x] Shared generated 25-bone anatomy and eleven animated hit volumes.
- [x] Vanguard, irregular and breacher with reference height/bulk, distinct headgear/equipment and carbine/AK-style weapons using shared grip/muzzle sockets.
- [x] Distance-driven walk/run/crouch, turning steps, wounded posture, sided regional hit reactions, reload and vault layers on the fixed simulation clock.
- [x] Planted terrain contacts, bounded pelvis/sole correction and rigid two-bone leg/hand IK; constrained spine/head aim and reload hand tracks.
- [x] One evaluator for authoritative hit volumes, visible/shadow poses and independent current/previous temporal palettes; +Y-along-bone joint frames with exact render offsets for ragdoll handoff.

**Implementation check:** The shared fixture checks all three variants in six poses through actual Bullet volumes (198 queries), connected hands, uneven support, running foot locks, production capsule traversal up four stairs, turning, damage reactions, pause and three resets. Unit samples cover all clips, rigid limb lengths, aim limits, joint-frame reconstruction and 30/60/144 FPS equivalence. Native/browser pose captures support visual inspection.

**Adaptations and remaining qualification:** Reduced procedural detail, static-ground foot anchors, analytic solves and bounded additive layers are documented adaptations. The carried magazine remains rigid, matching the reference soldier preview. Reload/vault animation interfaces are implemented; ammunition cycles, tactical vault decisions and root traversal remain step 11. Step 10 replaces the authored collapse with native Bullet ragdolls. Controlled reference motion/appearance, Kaigen capture and sustained performance remain steps 18–19; implementation completion is not visual-parity acceptance.

**Resource account:** Three shared meshes: 9,804 / 9,804 / 10,488 vertices and 2,166,912 total stream bytes (2.07 MiB); two additional buffers and 1,652,832 additional bytes. Six actors retain 78 objects, 66 hit volumes, 25 joints and the existing pass/palette counts. Variant dimensions scale collision volumes with the mesh. Two ground rays per actor per fixed tick add at most 1,440 rays/second for six live actors. No new render targets or native extension.

**2026-10-19 validation:** 296 standalone checks across 31 Lua suites and the 12 baseline-tool checks pass. Native Metal and release Chrome WebGL2/ANGLE Metal each pass 11 shared checks and save 15 pose captures. Reports are under `build/soldier-native-validation` and `build/soldier-browser-validation`; commands and limits are in README.md. These are implementation checks, not sustained-performance or cross-engine qualification.

### 10. Add rigid-body debris and ragdoll deaths — IMPLEMENTED

- [x] Native Bullet casings, dropped magazines and impact fragments, with collision/CCD, settling, sleep, bounded pooling and simulation-time lifetime cleanup.
- [x] Eighteen bodies and seventeen cone-twist constraints per soldier, mapped from the live procedural skeleton with inherited velocity and regional lethal impulses.
- [x] World-occluded blast impulses, physical corpse bullet reactions without further damage, matching visual/shadow/temporal interpolation and pause/capture/reset lifecycle handling.

**Implementation check:** The shared native/release-WebGL fixture exercises six deaths on floors, stairs and beside a wall, pause/resume, all-body sleep, blast wake-up/occlusion, corpse shots, production shell/reload events, pool saturation, debris collision/sleep, natural expiry and ten death/restart cycles. Thirteen checks and five captures per backend are stored in `build/physics-native-validation` and `build/physics-browser-validation`. All 32 standalone Lua suites pass, including 30 pure handoff/anchor/region checks; baseline-tool tests pass.

**Resource account:** At most 32 pooled debris bodies and 108 corpse bodies, 102 joints and 172 additional game objects (including 32 debris meshes). One shared 1,440-byte cube buffer, 64 mesh components, no new render targets or extension. Sleep skips physics sampling/pose solves; expiry returns to 64 pooled objects and zero active bodies/joints. Engine limits are unchanged.

**Adaptations and remaining qualification:** Box proxies, symmetric pose-centred joint limits, hand-attached weapons and world-only body collision masks are explicit adaptations. Whole-articulation sleep suspends native simulation after sustained pose stability; Bullet/blast impulses wake it. Corpse lifetime is 30 seconds; fragments/cases/magazines use 8/10/18 seconds. Controlled reference motion, exact appearance and sustained total CPU/GPU performance remain steps 18–19.

### 11. Complete AI perception, weapons and tactics — IMPLEMENTED

- [x] Visual acquisition, pursuit, squad alerts, protected cover, low-cover peeking, suppression and coordinated flanks.
- [x] Event-position hearing of shots, footsteps and explosions with wall attenuation, bounded investigation/search and reachable wounded retreat; aim and damage reactions no longer consult unseen live player coordinates.
- [x] Thirty-round magazines, completed-clip reload transfers, actor-scoped audio/debris beats, 3–7-round bursts, variant weapon/accuracy profiles and pressure-dependent spread/cadence.
- [x] Capsule-checked tall-cover side peeks, rotating squad peek permissions, recent-visual-position suppressive fire and flank/reposition choices using all five routes and reachable lateral graph nodes.
- [x] Short low-obstacle vault links reuse the traversal sweeps, support checks and animation, preserving friendly firing lanes and route recovery.

**Implementation check:** The shared native/release-WebGL fixture covers real-wall hearing, search, three reload profiles/pause, expiring suppressive fire, side-peek withdrawal, wounded retreat, accepted/rejected vaults, six-actor full-map engagement/contact loss and five death/restart cycles. Unit coverage includes cross-presentation-rate simulation, finite magazines, historical evidence, exclusive/released claims and blocked/friendly firing lanes. Commands, reports and captures are documented in README.md.

**2026-10-19 validation:** All 33 standalone Lua suites pass (314 logged checks), plus the 12 baseline-tool checks. Mac Metal and release Chrome WebGL2/ANGLE Metal each pass thirteen shared behavior/resource checks and five captures, including full-map movement by all six actors, contact-loss cleanup and five death/restart cycles. The browser fixture uses a 0.1 s catch-up cap with 120 Hz fixed steps; its production-default-cap attempt reached the wall-time limit after ten checks. This timing accommodation is documented and is not a performance pass. Reports are under `build/ai-tactics-unit-validation`, `build/ai-tactics-native-validation` and `build/ai-tactics-browser-validation`.

**Resource account:** Seventeen tall-cover candidates extracted from existing walls increase metadata from 25 to 42. Geometry, collision shapes, actor resources, render targets, atlas tiers and generated audio bank are unchanged. Existing 32-slot debris, 24-voice audio and shared navigation budgets remain in use.

**Adaptations and remaining qualification:** One peek permission per squad, ray-attenuated hearing, authored graph routes/local vault links, unlimited reserve magazines and port-specific damage/accuracy/speed tuning are explicit. Controlled source behavior/motion comparisons and sustained CPU/GPU performance remain steps 18–19.

### 12. Implement enemy grenades — IMPLEMENTED

- [x] One grenade per actor, source-range/fresh-contact decisions, independent timing RNG, exclusive squad grants/cooldowns and a left-hand windup/release socket shared with animation.
- [x] Elevation-aware ballistic lobs with preflight/release sphere clearance, six reserved bouncing Bullet spheres, 2.35-second fixed-tick fuses, 6.5-metre obstruction-aware blast damage and existing/new-ragdoll impulses.
- [x] Throw/fuse/explosion events, player pressure, basic nearest-danger direction/height/fuse warnings, generated spatial blast sound, bounded flash/smoke and light. Full presentation matching remains steps 13, 15 and 16.
- [x] Pause/focus freezes both motion and fuse time; death/interruption releases throw grants; restart removes active/pending bodies, queued blast damage, warning/FX/audio and restores inventory.

**Implementation check:** Normal AI launches through the same path exercised by fixtures. Every blast queues at most one combat-owned damage request per living actor (including the thrower); walls/floors block wounds while occluded blasts retain pressure. Connected cues close the basic end-to-end gate. Matched reference presentation and sustained performance remain steps 18–19.

**2026-10-20 validation:** 330 standalone Lua checks passed, including 16 grenade-specific checks. Native Metal and release Chromium WebGL2/ANGLE Metal each passed eleven shared scenario checks with four captures: actual animated AI release, sphere/floor/wall bounce, arc rejection, focus/pause/resume, wall/upper-floor damage protection, one damage application per actor, blast death/impulse handoff and three pending/airborne restarts. All 77 native/Wasm audio samples match Lua; a trusted canvas click and analyser verify live Web Audio output. The thirteen-check native debris/ragdoll regression also passes. Browser fixtures retain step 11’s `engine.max_time_step=0.1` setting. Reports are under `build/grenades-unit-validation`, `build/grenades-native-validation` and `build/grenades-browser-validation`.

**Resources/adaptations:** Six dedicated slots add twelve objects and one 12,000-byte generated mesh buffer; common dynamics now reserve 76 objects / two buffers / 13,440 vertex bytes, with up to 146 bodies including six full ragdolls. Audio grows to 77 samples / 1,698,124 WAV bytes; existing FX and light pools are reused. Hand animation, elevation correction, arc/friendly clearance, 0.02 linear grenade damping, no prop-to-prop collisions, nearest-threat text warning and compact blast synthesis/FX are explicit port adaptations.

### 13. Complete combat and ambient effects — IMPLEMENTED

- [x] Retain tracers, Bullet casings/debris, muzzle flashes/lights and soft smoke; add twelve distinct surface recipes for sparks, chips, splinters, glass, blood, clods, splashes, leaves and fibres.
- [x] Add cooling, velocity-aligned sparks and swept ballistic fragments with bounded bounces; wood/metal/masonry mark variants, ray-projected blood spatter and scorch marks. Moving-body metadata prevents static marks on debris or ragdolls.
- [x] Add explosion fireballs, expanding shockwaves, debris/embers, a finite smoke column, existing spatial blast light and receiver-tested scorch marks. Actual player footsteps/landings and soldier death notifications emit dust.
- [x] Add camera-local dust motes, smoke sources at all three authored wrecks, daytime ground shimmer and hot-gas/shockwave refraction. World-only rays and opaque depth constrain receivers/intersections; glass and colour particles retain one sorted submission after TAA. Coverage-weighted colour companding and correlated dithering preserve faint gradients in RGBA8; encoded-space overlap blending is an explicit fallback approximation.
- [x] Reserve bounded combat/fragment, ambient, decal, haze and emitter pools. Pause/focus freezes age and emission; restart clears transient effects and reinstates only the three persistent sources. Teardown releases meshes/buffer/targets.

**Implementation check:** Production projectile, grenade, movement and death paths drive the same effects as the shared native/browser fixture. Procedural masks, reduced counts, point-swept visual fragments, planar depth/normal-clipped decals, authored wreck sources and RGBA8 offset accumulation are explicit adaptations. Controlled reference transient timelines/Kaigen capture and exact appearance remain steps 1/18–19; this is not a full visual-parity or sustained-performance claim.

**2026-10-20 validation:** All 34 standalone Lua suites pass 341 checks. Native Metal and release Chrome WebGL2/ANGLE Metal each pass 13 shared scenario checks, 15 captures and eight pixel gates: surface differences, soft intersections, hidden smoke/haze, scorch, glass sorting, visible heat refraction and exact effect/heat on/off/return restores. Native captures use a 1920×1280 framebuffer, browser captures 960×640; pixel gates compare only within each backend. Fixed capture comparisons disable TAA, exposure adaptation, motion blur, grain and ADS depth of field. Real landing/footstep/death events, fragment collisions, pause/focus and three restarts pass. A 60-second simulation-pressure sequence emits 600 impacts and 30 explosions with fixed resources; this accelerated sequence is not a wall-clock performance benchmark. The existing native combat-rendering regression passes 15 photographic toggle checks plus resize, motion, live firing and lifecycle checks; all 12 baseline-tool checks pass. Reports are in `build/effects-unit-validation`, `build/effects-native-validation`, `build/effects-browser-validation` and `captures/rendering/combat-validation`.

**Resource account:** 128 combat particles (48 reserved for swept fragments), 32 ambient particles, 48 decals, 12 distortion sprites and eight emitters. The 220 preallocated meshes share one 144-byte quad buffer (164 more objects than the prior 56-slot pool). One half-resolution RGBA8 offset target adds 0.879 MiB at 1280×720; the warp reuses an idle full-resolution radiance target and skips both draws when no haze is active. Mesh/collection capacity increases to 896/3072 for the full map plus effects/ragdolls. No audio bank or native extension is added.

### 14. Complete animated atmosphere and lighting matching — IMPLEMENTED

- [x] Fixed daylight/sunset/night, cloud decks, sun/moon/stars, environment updates, volumetric fog and window shafts.
- [x] Continuous solar/lunar trajectories, twilight/horizon transitions, midnight wrap, independent cloud/fog clock, shared moving cloud influence on surface sunlight and advected fog density.
- [x] Coordinate complete sky/environment endpoints, direct light, shadow fits, exposure limits and weather inputs through staged GPU updates and radiance blending. Eight sky strips plus nine environment rows keep weather work to two draws per update; explicit seeks publish atomically, continuous updates retain temporal history. Pause/focus freezes in-flight work; addressed captures remain deterministic.
- [ ] Match equivalent reference lighting/atmosphere views on the full geometry; refine the current bounded scattering approximation where comparisons show a quality gap.

**Implementation check:** Fixed states and addressed cloud/fog poses return exactly, while staged complete-map blends avoid exposing partial reflections. The reference trajectories, 4.2 m/s wind and shared cloud recipe are retained. The 61-degree map rotation, sampled weather latency, 0.2-second blends, single shadowed key, approximate twilight scattering and mean-density fog extinction are explicit adaptations. Full-map dawn/day/sunset/twilight/night views are inspected; exact reference lighting/radiometry and controlled Kaigen comparison remain steps 18–19. This is not a full visual-parity or sustained-performance claim.

**2026-10-20 validation:** All 34 standalone Lua suites pass 345 checks. Native Metal passes eleven fixed-view exact returns plus fog, shafts, resize and temporal camera sweeps. Native and release Chrome WebGL2/ANGLE Metal each pass eight shared scenario checks, 18 captures and 13 within-backend pixel gates, including an eight-solar-hour continuous transition through sunset and midnight, cloud-shadow contribution, exact sky/environment/fog restores, pause/focus and three restarts. Resource, render-command capacity and context-rebake scheduling tests pass; these do not close forced WebGL context recovery. Reports are under `build/animated_atmosphere-*-validation` and `captures/rendering/atmosphere-validation`. A short 1920×1280 native CPU sample records renderer-script median 0.266/0.492 ms fixed/animated (p95 0.388/0.638 ms; 49/46 samples). These are diagnostic submission timings; GPU/sustained-budget qualification remains open.

**Resource account:** Six persistent staging targets add 12.134 MiB HDR / 6.067 MiB encoded RGBA8. Default high-photo settings own 50 steady / 53 loading targets; disabling motion blur/DOF releases their two existing targets as before. Each weather update issues at most two extra draws and never regenerates material atlases. Weather values are packed into the existing lighting constant array to remain within Metal's buffer-binding limit; no surface sampler, native extension, geometry or audio resources are added.

### 15. Complete audio content and spatial processing — IMPLEMENTED; PARITY OPEN

- [x] Generated weapon/reload/player/surface sounds, ambience and bounded mixing.
- [x] Soldier stride footsteps and eight throttled formant bark patterns; one-per-round travelled near-miss cracks/whizzes, grenade pin/bounce/explosion and real ragdoll-contact cues, heartbeat, hit/headshot/kill/UI sounds and independent distant battle scheduling.
- [x] Reference-profile sub/mid/bolt weapon layers, and physical casing-contact sounds with rest/multi-contact rejection. Enemy reload bolt events resolve to an audible sample.
- [x] Continuous two-height obstruction probes and synchronized dry/muffled/wet crossfades, distance darkening, twelve reflection taps with room/outdoor blends, ambience ducking, cover-reduced deafening/tinnitus and recovery. Pause/focus/reset own clocks, pending cues and all playback layers.
- [x] Implement and qualify the portable layered-PCM path using the existing offline synthesis extension and Defold mixer, with explicit resource accounting and native/Wasm waveform comparison.
- [ ] Complete matched reference timbre/listening review. The proposed stereo/sparse-response adaptation is not yet accepted as an HRTF/full-convolution equivalent; front/back/elevation localization, five convolution spaces and propagation delay remain open.

**Implementation check:** Real Bullet contacts and travelled rounds drive cues; simulation RNG remains independent. The fixed bank owns 234 WAVs / 10,611,456 bytes, with 24 logical voices over 72 sound components, a 64-cue queue and four continuous two-ray emitter probes per presentation. Layer peak budgeting bounds output; no GPU resources or new real-time DSP extension are introduced. See README.md for the test commands, adaptation limits and qualification evidence. This does not establish full audio parity or sustained performance.

**2026-10-20 validation:** All 34 Lua suites pass (19 audio checks), plus 12 baseline-tool checks. Native Metal and release Chrome WebGL2/ANGLE Metal each pass 16 shared integration checks and 234 exact within-backend native/Lua waveform comparisons. Real output, stereo, live filtering, Bullet contacts, projectile near passes, AI steps, heartbeat, pause, three restarts and bounded event pressure pass; the original native gameplay audio suite also passes six restarts and real fire/reload/enemy cues. The 120-shot/480-impact pressure fixture peaks at 0.620 native / 0.619 WebGL. A separate verification-disabled native launch reports 202.482 ms synthesis CPU and 2.235 ms peak update while browser work ran concurrently; no sustained-budget claim is made. Reports are under `build/audio-content-*-validation` and `build/audio-validation`.

### 16. Complete HUD feedback — IMPLEMENTED

- [x] Core HUD, compass, geometry minimap, killfeed, pause and encounter restart.
- [x] Live enemy minimap contacts with above/below hints; four projected danger/fuse warnings following real grenade bodies, including behind-camera markers and separated warning rows.
- [x] Sixteen confirmed-hit damage numbers, hit/head/kill colours and timed elimination banners; six simultaneous seven-segment damage arcs retain hit bearings and rotate with the camera.
- [x] Low/empty ammo colours, independent chamber indication, 17/30/32 magazine pips, actual reload progress and magazine-out/in beats; low-health pulse and recovery feedback. Existing event-driven confirmation, grenade, reload and heartbeat sounds are reused without duplicate playback.
- [x] Optional six-objective world/minimap display and key/text/subtext/hold-progress prompt contracts. These displays do not create objectives, interactions, XP or a new game mode.
- [x] Bounded GUI pools, pause/death/inspection/diagnostic/restart lifecycle, native and release WebGL verification, and five window layouts.

**Implementation check:** Combat events own hit confirmations; live actors and Bullet grenade bodies own contacts/warnings. Projection includes rendered eye, yaw, pitch, roll, FOV and actual aspect ratio. The increment adds 156 preallocated GUI nodes and removes four legacy direction nodes; the scene cap is 1,024, with no new textures, render targets or audio resources. Messages are split into bounded records below the engine payload limit. The existing 44-metre north-up geometry map, default font, simplified glyphs and confirmation text without fictitious XP are retained adaptations. Controlled cross-engine visual acceptance and sustained cost remain steps 18–19.

**2026-10-21 validation:** Seven related Lua suites pass (90 checks). Native Metal and release Chrome WebGL2/ANGLE Metal each pass 15 shared integration checks, including real combat/grenades, rendered GUI receipts, all three magazine capacities, event pressure, expiry, pause, death, three restarts and optional display contracts. Each backend captures combat at 960×640, 1280×720, 800×600, 1440×600 and 400×600 plus reload and recovery. Portrait is a resize regression, not mobile/readability qualification. Reports/captures are in `build/hud-feedback-*-validation`; reproducible commands are in README.md. No sustained-performance or full-reference-parity claim is made.

### 17. Complete input adapters and user settings — IMPLEMENTED

- [x] Keyboard/mouse gameplay and menus, WASD/arrow alternatives, Ctrl/C crouch toggle, Z prone toggle, I/F inspection, 1–3 weapon selection and directional wheel switching. Diagnostic views/course/range/restart move to F1–F5/F9; 0 returns to play.
- [x] Full mapped gamepad actions: analog move/look, radial dead zone, fixed-tick aim response, sprint/stance toggles, combat/weapon actions, lean, menu navigation/repeat and disconnect pause. Held sticks/triggers require neutral after lifecycle transitions.
- [x] Simplified touch layout, as authorized on 2026-10-21: six combat buttons plus pause, wide right-side swipe look, fire-drag aiming and finger handoff, ADS slowdown, automatic sprint with hysteresis and fire/ADS cancellation, crouch/stand and jump/mantle. Portrait/landscape layouts, safe areas and large compact settings menus. Prone, lean, inspect and fire-mode touch buttons are intentionally omitted.
- [x] Independent mouse/touch/gamepad sensitivity, 55–100-degree vertical FOV with existing motion/ADS modifiers, invert look and Reset controls. Common simulation commands, independent source holds/movement and settings retained over restart.
- [x] Browser compatibility-mouse filtering, including release engines without `action.source`; actual touch audio activation without autoplay overrides, pointer lock, keyboard/wheel input and standard browser gamepad mapping.
- [x] Whole-game preset selection and automatic/default quality mode are implemented by step 18.

**Implementation check:** Touch GUI has bounded reused nodes and adds no textures or render targets. A smaller touch menu exposes essential controls/audio/display settings; desktop retains advanced display settings. Reset controls resets input preferences, while automatic quality defaults belong to step 18. Native action fixtures and Chromium browser gestures do not certify physical mobile/controller comfort, hardware mapping, Safari or sustained performance. Those limits remain explicit.

**2026-10-21 validation:** Six related Lua suites pass 73 checks; the baseline tools pass 12. Release Chrome WebGL2/ANGLE Metal passes nine integration groups and eight captures across 844×390, 390×844, 667×375 and 1024×768: real touch audio activation, multi-finger movement/look/fire and handoff, ADS/stance/reload/switch, settings/defaults, held-finger resizing, focus/death/restart, cancellation, real pointer lock/keyboard/wheel and browser gamepad mapping/disconnect. Native GUI and action fixtures cover the same core controls, seven layout/menu captures, keyboard alternatives and gamepad quarantine. Native touch/controller events and focus are fixture-driven; hardware comfort and mapping remain unqualified. Reports/captures: `build/input-browser-validation` and `build/touch-validation`.

### 18. Complete quality scaling and sustained performance — PARTIAL

- [x] Budgeted generation, bounded pools, resource snapshots, material tiers, photographic tiers and short diagnostic timing samples.
- [x] Provide Low/Medium/High/Ultra presets spanning scene scale, cascade resolution, resident material mip selection/shading, active FX density, decals and photographic processing. HUD stays at framebuffer resolution. The configured atlas capacity and fixed mesh pools remain resident; no runtime material rebake.
- [x] Add automatic adjustment toward the recorded 60 FPS target, manual selection and Defaults restoring Auto. Wall-clock windows, settling periods and failed-upgrade backoff prevent rapid oscillation. Pause/loading/focus/capture/resize samples are excluded; advanced quality edits select Custom. Policy and preset values are Defold adaptations, not identical Kaigen upscaling.
- [ ] Profile and optimize full-map generation, shader warm-up, route-planning spikes, animation/palette uploads, draw submission and physics/FX/audio under sustained combat.
- [x] Record three High release runs per backend at an actual 1280×720 framebuffer, each with 60 seconds of warm-up and 300 seconds of live traversal/combat; retain raw wall-clock update intervals, measured process RSS, initialization timing, workload counters and compiled bundle hashes.
- [ ] Complete per-preset measurements, GPU memory, verified presentation and CPU/GPU frame timing, cold loading, shader traces and thermal behavior; optimize the observed browser frame-time failures and native outlier.

**Implementation validation (2026-10-21):** Ten quality-policy Lua checks pass. Native Metal and release Chromium each pass 11 shared checks covering all presets, live combat/grenade/ragdoll switching, ten quality/restart cycles, resizing, Defaults/manual settings, focus and capture restoration. Native records ten screenshots. Chromium adds a real-mouse selector/Defaults check (12 total) and an eleventh screenshot; the real-touch input suite also exercises quality selection and Defaults across four layouts. All 111 focused Lua and 12 baseline-tool checks pass. Counts and estimated target bytes return to baseline; material bake counts remain unchanged. Reports are in `build/quality-native-validation` and `build/quality-browser-validation`.

**Sustained evidence (2026-10-21):** On the M3 Pro / 18 GiB Mac, native High p95 update intervals were 13.2–14.8 ms, peak RSS 237.5–249.3 MiB, with one run reaching 359.7 ms worst. Browser High p95 was 56–78 ms, peak RSS 1,267.3–1,323.7 MiB, and worst 126–514 ms. All six runs completed with zero route stalls and constant target counts. These are wall-clock updates, not verified presentation or CPU/GPU timings; browser High fails the proposed budget. One earlier browser loading timeout is retained with an unconfirmed cause. A short 30+60-second browser Auto run verified two real-clock downgrades to Low; its p95 update interval was still 40 ms, so adaptation does not close the performance gate. Full tables, scope and reproducible commands are in README.md; raw results are under `build/quality-performance-*`.

**Completion check:** The step-1 budgets hold during movement, firing, grenades and ragdolls, with no lazy shader-compilation stalls or progressive resource growth. Each preset has measured quality/cost evidence. GPU/CPU timings, presentation timestamps, shader/thermal traces and full per-preset sustained qualification remain open.

### 19. Close cross-engine and platform qualification — OPEN

- [ ] Complete matched still/motion, gameplay and audio comparisons against both references after geometry, lighting and content converge. Use exact pixel checks only for controlled within-backend regressions.
- [ ] Run the full traversal, weapons, six-actor AI, grenades/ragdolls, audio, HUD/input and pause/restart scenarios on the target Mac native and desktop browser builds. Physical mobile qualification is deferred.
- [ ] Qualify floating-point HDR renderability/filtering/blending beyond Metal; retain and verify the encoded fallback where needed, with limitations recorded.
- [ ] Resolve and requalify the recorded forced WebGL context-restoration failure (`OpenGLSetRenderTarget` / `GL_FRAMEBUFFER_UNSUPPORTED`) and generated-resource recovery. Lua rebake tests alone do not close this gate.
- [ ] Exercise resizing, focus/background transitions, repeated quality changes and long combat sessions on the target Mac native and desktop browser backends.
- [ ] Update README.md and this status ledger with reproducible commands, reference/build fingerprints, captures, sustained measurements and any explicitly accepted deviations.

**Completion check:** All required parity scenarios and device budgets have evidence. Missing Kaigen captures, incomplete geometry/lighting matching or unqualified device paths prevent an unqualified claim of full parity.

## Scope boundaries

- The user selected Mac native and desktop browser at 60 FPS on 2026-10-15. The simplified touch-control adaptation is implemented in step 17, but physical mobile performance/platform qualification is outside the current acceptance gate.
- Enemy grenades are required parity work. Kaigen documents player melee, use, grenade and flashlight bindings as inactive; those bindings do not establish implemented player features to port.
- Objective/prompt APIs do not establish an objective-based game mode. Multiplayer, progression and additional weapons are outside this parity plan.
- Saved preferences remain an optional Defold follow-up. Session settings already survive encounter restart; persistence was not established as a reference feature by this audit and is not a parity gate.
- Equivalent implementations may satisfy visual/audio behavior without duplicating the reference engine's renderer, physics solver or DSP internals. Record observable differences and verify them before accepting an adaptation.

## Historical implementation record

The sections below preserve the original subsystem plan and incremental validation history. Their numbered subsystem/rendering sequences are historical, not the remaining execution order. Test counts, resource costs and statements such as “not part of this step” apply to the increment being described; the current status tables and ordered backlog above take precedence.

**What the two implementations tell us**

| Area | Three.js version | Kaigen version | Implication for Defold |
|---|---|---|---|
| Architecture | Eleven systems, shared context, events, fixed-step simulation | C modules using engine ECS resources and scheduled systems | Preserve subsystem boundaries, but implement them using Defold scripts and Lua modules |
| World | Explicit street/building layouts, procedural geometry, material batching, repeated props | Closely follows the same layout and generation approach, with parallel generation and engine uploads | Port the layout data and generation algorithms |
| Physics | Custom triangle BVH, swept capsule, rigid bodies and ragdolls | Engine physics and reusable character controller | Use Defold Bullet where practical; implement the movement rules above it |
| Rendering | Extensive custom HDR pipeline layered onto Three.js | Engine renderer plus game-specific shaders and post effects | Build a focused Defold render pipeline, expanding it incrementally |
| AI | Walkability grid, A*, cover selection, perception and squad coordination | Engine navmesh routes plus game-specific cover and combat logic | Keep the behavior; supply a Defold navigation implementation |
| Audio | Web Audio synthesis and processing | Samples synthesized at load, then played through the engine | The Kaigen approach maps well to Defold's runtime sound resources |

The original [architecture contract](/Users/bjornritzl/Downloads/Claude-of-Duty-main/ARCHITECTURE.md) is useful as a feature and event reference. The [Kaigen application loop](/Users/bjornritzl/Downloads/kaigen-claude-of-duty-main/src/claude_of_duty/claude_of_duty.c) shows how those systems fit into another engine. These source links refer to the local reference checkouts used for this review.

A few details affect scope:

- The Kaigen game is predominantly C, despite being described as a C++ port. Its ECS, allocation, threading, rendering and physics interfaces are engine-specific.
- The map is largely an authored layout assembled procedurally. Keeping its streets, entrances, stairs and sightlines matters more than introducing random map generation.
- Both versions normally populate two squads of three enemies. That is a useful initial combat target.
- Player melee, use, grenade and flashlight inputs should not automatically count as completed features: Kaigen explicitly documents those bindings as inactive.

**Defold 1.14.0 is the baseline.** Its cubemap render targets are particularly useful for generating sky environments and reflections. Metal becoming the macOS default means shader validation should include Metal immediately. Shader storage buffers are available through dmSDK on supported backends, but should remain optional. Native extensions must also use the updated ABI. [Defold 1.14.0 release](https://defold.com/2026/10/12/Defold-1-14-0/)

The earlier Bullet improvements remain equally relevant: shape casts, contacts, constraints and collision meshes substantially reduce the physics infrastructure needed for the port. [Defold 1.13.2 release](https://defold.com/2026/09/29/Defold-1-13-2/)

**1. Build a small, explicit gameplay framework.**

Implemented: `main/controller.script` coordinates the six Lua systems in
`game/systems`, with buffered input, synchronous gameplay notifications, one
damage owner and separate interpolated camera/HUD presentation. The project uses
120 Hz fixed updates and metre-based 3D physics with gravity -20.6 m/s². Gameplay
systems beyond this foundation remain the work described below; see `README.md`
for the runtime contract and validation commands.

Use one controller script to coordinate Lua modules for player, weapons, AI, world generation, FX and audio. Defold game objects represent actors, cameras, renderable batches and collision objects.

Keep frequently accessed simulation state in Lua data structures. Use direct module calls within the simulation and messages for component interactions and discrete notifications. Preserve events such as firing, impacts, damage, death and footsteps, with one clearly defined owner applying damage.

Start with the source projects' 120 Hz simulation rate through Defold's fixed-update facilities. Update camera presentation, HUD and visual interpolation separately. Defold should own physics stepping; copying Kaigen's manual stepping loop would be inappropriate. [Fixed timestep settings](https://defold.com/manuals/project-settings/)

**2. Generate the world from shared descriptions of geometry, collision and navigation.**

The 50-metre street now connects an enterable two-storey W2 shop/apartment and
three-storey E2 shop/apartments. Shared recipes support either entrance side,
opposite stair directions and repeated upper floors. Three flights provide
standing headroom, true slab openings, guards and furnished rooms; collision,
floor-specific minimaps, room audio and bounded lights use the same dimensions.
W1/W3 closed facades now frame the west courtyard and alley; a rear lane around
W2 connects them into a second route between two street junctions. Shared layout
data supplies tiled dirt ground, collision, cover, minimap and route connections.
The layered graph has 93 nodes and 93 edges linking both buildings and the flank.
Native checks cover continuous player traversal, enemy routes between buildings
and floors, a full patrol circuit and alerted pursuit around W2. Light selection
follows the camera within the existing four-light budget. Loading remains bounded with independent
random streams. The expanded world stays within the existing resource limits
(77 mesh batches, 190 colliders, 0.71 MiB vertex streams). This advances milestone 3;
the remaining market layout, additional building recipes and browser/mobile
validation remain subsequent work.
See `README.md`.

Translate the original [layout](/Users/bjornritzl/Downloads/Claude-of-Duty-main/src/world/layout.js) into Lua data: buildings, floors, openings, stairs, alleys, furnishings and spawn points.

Give the generator outputs for:

- Visual geometry, grouped by material and spatial chunk.
- Simple collision volumes carrying surface identifiers.
- Navigation surfaces, doorway connections, stairs and cover candidates.
- Lights, spawn points and minimap geometry.

Defold Mesh components and runtime buffers support generated geometry. Every generated batch should include bounds for frustum culling. Avoid a game object for every brick or small decorative part. [Mesh documentation](https://defold.com/manuals/mesh/)

Begin with merged batches and reusable geometry recipes. Measure draw calls and memory before deciding how much custom instancing is needed; Three.js `InstancedMesh` should not be assumed to translate directly to runtime Defold meshes.

Generation should advance through budgeted loading jobs. Keep seeded random streams separate so changing decorative detail does not alter enemy placement or weapon spread.

**3. Use Bullet queries beneath a purpose-built character controller.**

Capsule movement implemented: fixed-tick walking/sprinting, mouse look,
jumping with buffering/coyote time, crouch/prone resizing with headroom checks,
overlap recovery, swept wall sliding, step-up, slope limits and ground snapping.
The optional traversal course (key 4) exercises stairs, ramps, corners, ceilings
and doorway widths through native Bullet. Camera interpolation and movement
events are wired. Tactical sprint, slides with steering and bounded jump exits,
clearance-checked mantles and collision-limited camera lean are implemented.
The expanded course covers mantle height, landing headroom, narrow tops and
approach obstructions. Automatic vaulting and full source camera effects are
outside this increment; full browser/mobile traversal validation is still required. See
`README.md` for controls/tests.

Port the movement behavior and tuning: acceleration, sprint, tactical sprint, crouch, prone, slide, jump buffering, mantle and lean. The original [movement tuning](/Users/bjornritzl/Downloads/Claude-of-Duty-main/src/player/tuning.js) is a better starting point than approximating the feel.

Implement a kinematic capsule controller using sweeps, contact resolution, step-up, slope limits and ground snapping. Test it on a dedicated course before introducing the full map. Defold exposes convex shape casts suitable for these queries. [Bullet world API](https://defold.com/ref/bullet3d.world-lua/)

One constraint deserves attention: the documented shape API can resize primitives and modify convex hulls, but cannot rewrite triangle-mesh geometry. Runtime-generated visuals therefore need an intentional collision representation. [Bullet shape API](https://defold.com/ref/bullet3d.shape-lua/)

The original [world assembler](/Users/bjornritzl/Downloads/Claude-of-Duty-main/src/world/builder.js) already separates detailed visuals from simple collision proxies. Follow that design, creating boxes and hulls from the same dimensions as walls, doorways and stairs.

**4. Preserve weapon behavior and give the viewmodel its own rendering pass.**

Implemented: source-tuned M4A1/MPX-9/P-19 definitions, independent magazine and
chamber state, auto/burst/semi fire control, deterministic recoil springs,
stance/movement spread, ADS, reload/inspect and weapon switching. Projectiles
retain travel, drop and full-segment Bullet checks, with measured box thickness,
material penetration and single-owner actor damage. Runtime-generated weapons,
magazines, bolts/slides and hands animate in a separate camera/colour/depth pass.
Surface particles, cases, tracers, an ammo/mode HUD and an optional native firing
range are included. Lua and macOS/Metal smoke suites pass. Geometry is simplified;
full presentation effects and full browser/mobile weapon validation remain later
work. Synthesized playback is implemented in step 7. See `README.md` for contracts
and deliberate source differences.

Port the rifle, SMG and pistol definitions, ammunition, fire modes, recoil springs, spread, ADS, reload and inspection timelines.

Retain simulated projectile travel and drop. Each simulation step should query the entire travelled segment so fast projectiles do not skip thin surfaces. Surface metadata should control penetration, impact effects and audio.

Generate weapon geometry at load. Animate major parts—magazine, bolt, slide and hands—through transforms and procedural poses.

Render the weapon with its own camera and depth buffer. The original [render pipeline](/Users/bjornritzl/Downloads/Claude-of-Duty-main/src/render/index.js) documents why it also separates the weapon from temporal effects and world fog. That distinction should survive the port.

**5. Treat procedural soldiers as an early technical prototype.**

Initial prototype implemented: one generated, 25-bone soldier with weighted Mesh
streams, a matrix-palette skinning shader, procedural idle/walk/aim/recoil and a
scripted death collapse. Seven skeleton-driven Bullet hit volumes connect to
existing projectile damage. The soldier patrols, detects, pursues, fires physical
rounds and navigates the street-to-shop route using the authored graph and swept
capsule controller. Key 9 restarts the encounter. Lua and native macOS/Metal
checks cover animation bounds, head/body hits, occlusion, return fire, navigation,
replacement and cleanup. A debug HTML5 bundle also passes a manual WebGL 2
rendering/movement/return-fire/restart check; physical mobile testing remains
outstanding. The skinning function is now shared with the shadow
pass added in step 6; terrain IK, ragdolls and source visual parity
are still subsequent work. The encounter now has two squads of three with stable
actor IDs, staggered perception, observed-position radio reports, exclusive protected cover claims,
friendly firing-lane checks and local separation. One actor can take the generated
west loop while a squad member engages. Claims release on death, invalidation and
restart; six independent health/animation states share one mesh buffer. This
advances milestone 4 with basic squad tactics; it does not complete combat parity.
The 119 Lua checks pass. Native Metal and HTML5/WebGL 2 scenarios verify protected
cover fire, a full rear flank during live engagement, six deaths and eight resets
without resource growth. Mean AI fixed-tick CPU is 0.98 ms native and 1.62 ms in
the browser on this Mac, with occasional route-planning spikes still to optimize.
These are debug measurements, not mobile budgets. See `README.md` for costs,
controls and validation scope.

Suppression and low-cover peeking are now implemented: actual travelled rounds
and nearby impacts build bounded, decaying pressure with per-round deduplication.
Enemies duck, stop firing, retain valid cover and resume timed peeks after recovery.
The planted-ankle crouch pose drives the mesh, shadows, perception, muzzle and hit
volumes; standing requires capsule clearance. Nine additional Lua checks and a
shared native Metal/HTML5 scenario validate real near misses, barrier impacts,
head concealment, firing recovery, pause/reset and deterministic timing. Tall-cover
side peeks and squad peek permissions remain subsequent work. The AI costs above
are the pre-suppression baseline; route-planning spikes remain to optimize.

The original soldiers use a generated mesh, a 25-bone skeleton, procedural pose layers and IK. Importing a prebuilt animated model would sidestep the runtime-generation requirement.

The proposed route is:

- Generate vertices, skin weights and joint indices into Mesh buffers.
- Maintain the skeleton and animation state in Lua initially.
- Upload a bone palette to a custom skinning shader.
- Use the same skinning in the shadow pass.
- Drive hit volumes and eventual ragdolls from that skeleton.

This needs a prototype to establish buffer layout, palette limits, upload cost and performance across graphics backends. Defold's imported Model animation support is useful, but should not be mistaken for an already-verified runtime skeleton construction API. [Model documentation](https://defold.com/manuals/model/)

Start AI with patrol, detection, pursuit, firing and death. Then add cover claims, suppression, flanking and squad coordination.

For navigation, generate a layered walkable graph from the building descriptions, validated through physics queries. A single height per X/Z cell is insufficient for overlapping floors. Stairs and doorways become explicit connections. Kaigen's navmesh behavior is the stronger reference for that part.

**6. Generate materials on the GPU and develop the renderer in stages.**

Initial renderer implemented: three GPU-baked material atlases cover plaster,
concrete, asphalt, wood, metal and cloth; a six-face procedural sky environment
was initially generated one face per frame (replaced by the filtered atlas in step 5). World, soldier and weapon share roughness/metalness lighting,
sunlight, ambient/reflection terms and up to four bounded local lights. A 1024²
sun shadow map uses the same animated soldier skinning as the colour pass.
Height fog, quarter-resolution bloom, shared tone mapping and an isolated weapon
colour/depth pass precede the GUI. Diagnostic views and effect toggles are exposed
through the Automation Bridge. The 72 Lua tests, native macOS/Metal renderer and
combat smoke suites pass, as does a focused HTML5/WebGL 2 visual/input check;
physical mobile validation is still outstanding. All fifteen planned surface recipes, material mip filtering and world weathering
are now implemented (steps 3–4 below);
Unified daylight, filtered environment lighting and interior attenuation are
implemented in rendering step 5. Stable cascaded sun shadows are implemented in rendering step 6. Depth/normals, ambient occlusion and contact shadows are implemented in rendering step 7. Temporal stability is implemented in rendering step 8. Reflections, transparent
glass, local-light shadows and muzzle lighting are implemented in rendering step 9.
Atmosphere is implemented in rendering step 10. Weapon/combat rendering is
implemented in rendering step 11. Final photographic treatment and desktop/browser
qualification are implemented in rendering step 12; sustained/mobile budgets and
full cross-engine parity remain open.
See `README.md` for resource budgets and validation scope.

**Rendering quality sequence — agreed 2026-10-14.** The target is the visual
quality of the Three.js and Kaigen reference versions. Preserve runtime-generated
materials and geometry. Prioritize surface richness, lighting and contact depth,
then stability in motion and atmospheric effects. The numbered steps below are
rendering steps, separate from the top-level implementation milestones.

1. **Repeatable visual comparisons.** Define street, interior looking outside,
   material detail, courtyard, hip-fire, ADS, sunset and night shots. Record
   camera position/orientation, vertical FOV, pixel dimensions, seed, lighting,
   exposure, quality and source revision. Hide UI and freeze gameplay. Add an
   opt-in generated material laboratory with panels, a floor, roughness spheres
   and a furnished corner, plus a deterministic slow camera sweep. Save stills,
   motion sequences and a comparison manifest. Separate exact within-backend
   regression comparisons from adapted cross-engine framing. Explicitly report
   unsupported lighting states and unavailable reference captures.
   **Gate:** Fixed, reproducible captures and motion samples establish the
   baseline; every later step produces comparisons and a rendering-cost report.

2. **HDR and colour pipeline.** Replace the fixed 0–8 encoded RGBA8 radiance on
   the main quality path with floating-point HDR. Verify renderability, filtering
   and blending on each backend first. Establish linear-light calculations,
   accurate sRGB conversion and one display conversion. Port the references'
   AgX tone mapper, initially using fixed exposure and a neutral grade.
   **Gate:** Bright sky, metal and dark rooms retain detail without clipping,
   banding or inconsistent world/weapon exposure.

3. **Full procedural surface recipes.** Port plaster, concrete, asphalt and wood
   first; brick, tile, dirt and gravel next; then painted/rusted/brushed metal,
   fabric, rubber and glass. Generate albedo/height, normals and packed
   occlusion/roughness/metalness with per-material physical scale and relief.
   Implement mipmaps, suitable filtering and storage that prevents tile bleeding.
   **Gate:** Materials remain distinct at near, medium and far distances without
   distant shimmer or atlas seams.

4. **Weathering and variation.** Add metre-scale discolouration, replastering,
   runoff, ground splash, dust, cavity grime and edge wear. Extend generated mesh
   data with wear/grime/occlusion masks. Add fading micro normals and selective
   close-range parallax; keep variation deterministic and surface-anchored.
   **Gate:** Whole façades have structure at several scales and close-ups show
   relief without an obvious repeating grid.

5. **Sunlight, environment and interiors.** Use one lighting configuration for
   the sun, sky, diffuse fill and environment reflections. Implement filtered
   reflection levels by roughness and a proper image-based lighting response.
   Port the references' interior-volume attenuation of skylight and bounce;
   preserve warm ground bounce, cooler sky fill and bounded room lights.
   **Gate:** Sunlit walls, shade, covered stalls and deep interiors have distinct
   illumination, with bright doorways into darker rooms.

6. **Stable cascaded sun shadows.** Add camera-following cascades, texel
   stabilization, blended boundaries, tuned bias and reference-like softness.
   Start with three/four cascades and choose resolution from measured quality and
   cost. Include matching animated and alpha-cutout shadow casters.
   **Gate:** Detail holds near the camera and coverage holds at distance without
   crawling, detached shadows or visible cascade seams during a slow sweep.

7. **Depth/normals, ambient occlusion and contact shadows.** Add a shared prepass
   for static and skinned geometry, GTAO-style occlusion with edge-aware filtering,
   and short depth-buffer rays toward the sun. Apply occlusion to the appropriate
   lighting terms and avoid double-darkening material cavities.
   **Gate:** Floors, furniture, stairs, window recesses and feet have convincing
   contact depth without black halos.

8. **Temporal stability.** Add camera, object and skinned motion vectors, then
   TAA with history rejection and neighbourhood clipping. Reset history after
   teleports, restarts and size changes. Antialias the weapon separately and
   composite it after the world's temporal processing.
   **Gate:** Thin edges, textures and highlights remain stable in motion without
   trails behind soldiers or ghosting/transparency on the weapon.

9. **Reflections, glass and local lights.** Add SSR for smooth materials with
   filtered environment fallback, an explicit transparent glass path, improved
   local-light selection and a bounded shadow budget for important local lights.
   Integrate muzzle-flash lighting.
   **Gate:** Metal, glass and masonry respond differently; reflections disappear
   gracefully at screen edges and room lighting does not visibly pop.

10. **Atmosphere.** Port the reference atmospheric sky, cloud layers, sun/moon
    appearance and matching environment updates. Establish fixed daylight,
    sunset and night before animating time. Add shadowed volumetric fog/window
    shafts with reduced-resolution rendering and edge-aware reconstruction.
    **Gate:** Distance reads convincingly, sunset retains colour and contrast,
    and indoor shafts follow real openings and occluders.

11. **Weapon and combat rendering.** Apply richer materials to weapons, gloves
    and soldiers; match their indirect lighting indoors. Add emissive flashes,
    depth-softened smoke/dust, impact decals and correct transparent sorting.
    **Gate:** Hip-fire, ADS and firing shots have consistent quality and readable
    sights, without particle rectangles, glowing dark metal or fogged weapons.

12. **Final photographic treatment and qualification.** Add multiscale bloom,
    controlled exposure adaptation, the generated reference colour grade and
    restrained sharpening. Add adjustable motion blur and ADS depth of field
    after temporal data is reliable; tune vignette and grain last. Record GPU
    time/memory throughout and derive quality presets from the measurements.
    **Gate:** The complete still/motion set has comparable contrast, colour,
    material richness and stability at the agreed performance target.

Steps 1–7 form the first substantial visual milestone. Full screenshot parity
also depends on geometry: bevels, façade recesses, balconies, clutter and weapon
silhouettes must be tracked wherever they limit a rendering comparison.
Step 1 is in progress: a versioned Defold capture catalogue, opt-in material lab,
frozen hip/ADS poses, frame-addressed sweep, manifest and comparison tools are
implemented. Native Metal captures verify exact repeat pixels, frozen simulation,
fixture cleanup and restoration of settings. A Three.js capture adapter uses the
same level-space cameras through its world transform. Kaigen captures, reference
laboratory coverage and matching time-of-day lighting remain open; sunset/night
were unsupported at that stage and are now implemented in rendering step 10. See `README.md` for
capture commands and the distinction between visual and pixel comparisons.
The overlap blocker is fixed: slabs and walls meet at butt joints, trim and
parapet corners no longer overlap, and box faces buried by adjacent solids are
clipped before upload. The world near plane is 0.1 m to improve depth precision
at close trim joints; the viewmodel retains its own near plane. All seven
supported shots match every RGB pixel across three independent Metal launches.
`tests/render_baseline.py --launches 3` makes this a strict regression gate.
Native collision checks also pass continuous player and AI traversal through
W2 and both E2 upper floors, including the return journeys and stair guards.
The Three.js street also matched exactly across two independent launches.

Step 2 is in progress: Metal uses linear RGBA16F for scene, weapon, bloom and
environment, with accurate sRGB transfer functions and the references' neutral
AgX curve at fixed exposure. The final composite performs the only display
conversion; GUI remains display-referred. GPU probes verify values above 8,
linear filtering, hardware blending, world/weapon coverage, transfer-function
knees and the reference curve at exposures 0.25/1/4. Native rendering smoke
checks also pass. Storage at 1280 × 720 rises from 26.35 to 33.91 MiB; the target
count remains nine. The encoded RGBA8 compatibility path remains available.
The HDR capture set also passes all seven shots across three fresh launches;
per-shot CPU scopes, submitted draws and target estimates are in the manifests.
Remaining step-2 work: qualify HDR renderability/filtering/blending on WebGL and
other native backends, test physical mobile devices, measure GPU frame cost,
and review the bright-sky/metal/dark-room motion set before closing the gate.
Unqualified backends deliberately retain the compatibility path; exposing an
RGBA16F enum alone is not treated as evidence of complete support.
The [Three.js pipeline](/Users/bjornritzl/Downloads/Claude-of-Duty-main/src/render/index.js),
[material library](/Users/bjornritzl/Downloads/Claude-of-Duty-main/src/materials/library.js),
and [Kaigen look configuration](/Users/bjornritzl/Downloads/kaigen-claude-of-duty-main/src/claude_of_duty/cod_look.c)
are the source references. Kaigen's engine implementation is not included in the
local checkout; its renderer integration must not be mistaken for a locally
verified engine build.

Step 3 implementation is complete: all fifteen requested surface recipes now
have GPU-generated linear albedo/height, physical-scale normals and packed
roughness/metalness/occlusion. Concrete floors, brick, tile, dirt, gravel,
painted/rusted/brushed metal, fabric, rubber and glass join the first four recipes.
Glass has an opaque recipe preview and the separate transparent pane path added in step 9.
The shared microdetail set and low/medium/high launch-time presets preserve stable
IDs, seeds and physical scale. Every preset includes full isolated mip chains,
wrapped borders, trilinear/two-tap filtering and normal-variance roughness correction.
The medium preset is the default and reduces target storage at 1280 × 720 from
102.49 to 93.72 MiB steady, with a 116.91 MiB bake peak. Low/high estimates are
46.19/283.66 MiB steady; high is explicitly a desktop preset. Loading is 926 jobs /
1394 draws on medium, with nine targets after scratch resources are released.

Step 4 implementation is complete: deterministic world-space discolouration,
repair patches, runoff, ground splash, dust, cavity grime and edge wear are wired
to the production world shader. Original face-edge distances and mesh
wear/grime/occlusion masks avoid treating visibility cuts or ground chunk seams
as worn edges. Runoff starts at visible wall/ledge boundaries. Interior finishes
have reduced exposure. Shared micro normals fade by distance and pixel footprint;
selective 12-step parallax fades at grazing angles, silhouettes and distance.
Unstructured materials use continuous world-space warping; brick/tile/plank
layouts retain their geometry. Occlusion masks do not double-darken baked cavities.

The expanded catalogue provides close-ups of every material, near/mid/far views
and three deterministic motion sequences of 121 frames each. All 31 supported
native views match every RGB pixel across three independent engine launches.
The 137 Lua checks, native GPU checks of all three presets and 53-stage WebGL
suite pass. GPU checks cover maps, wrapped mip borders, feature contributions
and camera return. See `README.md` and
`captures/rendering/surface-weathering-review/report.md` for comparisons, timing
samples and measured scope. The world still has 36,552 vertices and 190 colliders; additional material
assignments make 86 batches, and the extended mesh streams total 2.51 MiB.
Forced WebGL context restoration currently aborts in the engine framebuffer path;
the failed qualification is retained separately. Physical mobile qualification,
other native backends and sustained-combat GPU budgets remain open.
Step 2's WebGL/mobile floating-point HDR gate is also still
open: these browser checks use its compatibility path. Kaigen runtime comparison
remains unavailable because the local reference lacks its engine.

Step 5 implementation is complete: one daylight configuration drives sunlight,
shadow direction, sky, diffuse fill and environment reflections. A padded
396 × 594 atlas holds six GGX reflection levels, cosine-convolved diffuse light
and a two-channel integrated BRDF lookup, generated with deterministic 128-sample
integration. Direct and indirect lighting share Smith GGX visibility; the solar
disc is excluded from IBL to avoid counting direct sunlight twice. World,
soldier and viewmodel use the same lighting in world coordinates.

The two enterable building footprints and matching awnings supply four bounded
indirect-light volumes, independently of the four selected room lights. Exterior
wall faces and roofs retain outdoor lighting, while doorways admit a smooth,
limited fill into the shops. Sky-lit fog follows the same enclosure, avoiding
bright haze in dark rooms. Warm room/ground light and cool sky fill remain distinct.
The interior floor is tuned to 0.18 for the current fixed exposure. This remains
coarse volume-based visibility; local-light occlusion, GI and contact shadows are
not part of this step. Laboratory captures disable production volumes.

Medium HDR target storage at 1280 × 720 is 95.33 MiB steady / 118.52 MiB during
baking, an increase of 1.61 MiB from step 4. Nine steady targets and the per-frame
pass count are unchanged. Medium loading now uses 921 jobs / 1389 draws; the
whole environment is baked in one pass so discard-on-load backends retain all
tiles. Packed lighting uniforms keep Metal descriptor usage within its limit.

Step 5 validation passes 140 Lua checks, the native renderer and HDR suites,
and dedicated GPU checks of interior fill, unchanged bright doorway pixels,
roughness filtering, BRDF endpoints, cube seams and exact feature restoration.
The maximum sampled cube-edge difference is 0.51 of an 8-bit display value.
All 31 existing native views match every RGB pixel across three independent
launches. The laboratory, grazing-road and façade sweeps each contain 121 frames.
The WebGL 2 compatibility path passes 57 stages plus map/feature/return pixel
checks on Chromium / ANGLE Metal / Apple M3 Pro. Its resources were compiled
locally and bundled with the existing cached debug engine.

Before/after comparisons are in `captures/rendering/lighting-review`; adapted
Three.js comparisons are in `captures/rendering/lighting-vs-threejs`. The final
capture source fingerprint matches the implementation. `lighting-review/costs.json`
records CPU/draw comparisons and short browser GPU samples: native street draws
remain 158 and render-script median CPU remains 54 µs; WebGL street median GPU
is 3.76 ms versus the prior 3.31 ms sample at 1024². These short, separate runs
are diagnostic, not sustained-combat or mobile budgets. Dark interiors retain
material detail around a brighter doorway; roughness rows broaden sky reflections
without cube seams. Geometry and reference time-of-day differences remain.

Physical mobile, other native backends, WebGL floating-point HDR and sustained
GPU budgets remain open. Forced browser context recovery was not requalified
in this step; the previous engine failure remains recorded. Step 6, stable
cascaded sun shadows, is implemented below.

Step 6 implementation is complete: four camera-following 1024² sun cascades
share one 2048² atlas, covering camera depths 8/22/52/120 m. Rotation-invariant
sphere fits include overlapping 12% blend bands, 12-texel guard space and 80 m
upstream caster coverage. Light-space origins snap to whole texels; each cascade
culls static and animated batches against its own projection. The final slice
fades out. Geometric-normal/world-texel bias, eight blocker taps and nine bilinear
comparison taps provide bounded contact-hardening softness without temporal
screen noise. Atlas taps cannot cross tiles; one clear and one render pass
preserve all cascades on discard-on-load backends.

Colour/shadow passes share animated skinning and procedural cutout coverage.
The capture laboratory adds a perforated panel and remote occluders 160 m away;
new distance/cutout sweeps and cascade/visibility debug modes expose the quality
gates. Target/sampler count is unchanged, while the larger shadow atlas adds
24 MiB: medium HDR at 1280 × 720 is 119.33 MiB steady / 142.52 MiB baking.
Validation passes 145 Lua checks, native renderer/animated-caster and dedicated
shadow GPU checks. All 34 native views match every RGB pixel across three fresh
launches, with five 121-frame sweeps. WebGL 2 compatibility passes 67 stages and
pixel checks, including projected cutout holes and remote coverage. Street draws
rise from 158 to 398, native render-script median CPU from 54 to 85.5 µs, and the
short 1024² browser street GPU sample from 3.76 to 6.25 ms. Comparisons and scoped
costs are in `captures/rendering/shadows-review`.
Physical mobile, other native backends, forced browser context recovery and
sustained combat budgets remain separate qualification work. Step 7, depth/normals,
ambient occlusion and contact shadows, is implemented below.

Step 7 implementation is complete: a shared static/skinned prepass stores
logarithmic depth and octahedral geometric normals in portable RGBA8, including
the same perforated coverage as colour/shadows. Half-resolution GTAO-style
horizon integration and 0.4 m sun rays feed a full-resolution normal/plane-aware
bilateral resolve. AO affects indirect light only and combines with material
cavities by minimum; contact visibility affects sunlight only and combines with
cascades by minimum. The separate weapon, particles and GUI are excluded.
Independent toggles and depth/normal/raw/resolved diagnostic views are exposed.

The new targets add 11.43 MiB at 1280 × 720; medium HDR now estimates
130.76 MiB steady / 153.94 MiB bake peak, with twelve steady targets. Static
prepass, optional skinned prepass and two fullscreen draws add contact depth.
The native frozen street has 468 submitted draws versus 398 with effects off.
Fixed spatial samples avoid frame noise but retain some AO diagnostic banding;
offscreen occluders, temporal filtering and physical mobile qualification remain
open. Validation passes 146 Lua checks, native renderer/HDR and projected
contact/depth checks, 36 views with exact pixels across three launches, five
121-frame sweeps and 89 WebGL stages with pixel assertions. See `README.md`
for costs, limitations and local before/after artifacts.

Step 8 implementation adds camera, rigid-object and skinned motion vectors,
eight-sample projection jitter and a world TAA resolve with per-tap depth/normal
history rejection and variance neighbourhood clipping. Previous displayed bone
palettes and root transforms preserve actor motion independently of simulation
interpolation. Teleports, restart, camera/projection cuts, resize, settings and
context restoration invalidate history. The weapon has its own spatial AA pass
in linear premultiplied colour and is composited after world temporal processing.

The laboratory now shares production face clipping and edge stitching at its
table/floor joints, which removes a subpixel capture instability.
Independent toggles and motion/history diagnostics are exposed in the menu and
automation. Still captures allow two transform-settling frames, converge for 32 history
samples, then hold; live capture sweeps
retain continuous history and expose the resolve's real cost. The extra targets
add 42.19 MiB on HDR at 1280 × 720 (31.64 MiB on encoded RGBA8): medium HDR is
172.94 MiB steady / 196.13 MiB baking, with sixteen/nineteen targets. Each actor
uploads current/previous palettes through 76 matrix-property calls per displayed
frame. Native validation passes 152 Lua checks, renderer/HDR/occlusion, combat/UI
and temporal suites. All 36 supported views match exactly across three launches;
a 61-image sweep retains continuous history. The short street A/B sample is
468 → 470 draws and 96 → 122.5 µs median render-script CPU, not a GPU budget.
The WebGL 2 compatibility path passes 97 stages with material, contact and
temporal pixel checks; diagnostics remain separate from radiance history.
Step 9 is implemented below. Cross-backend/mobile qualification and the earlier
outstanding reference/HDR gates remain separate.

Step 9 implementation is complete: smooth opaque materials trace current-frame
screen-space reflections with depth refinement and edge/roughness/distance fallback
to the filtered environment. The resolve replaces the existing indirect specular
term before world TAA. Separate thin glass panes use procedural smudges, two-sided
Fresnel reflection, depth rejection, back-to-front sorting and linear premultiplied
composition after TAA, including on encoded RGBA8. Two generated shop display panes
and dedicated reflection/glass/local-shadow laboratory captures exercise the paths.

Four persistent room-light slots now use hysteresis and fade-through-zero
replacement; teleports/captures reset immediately. A separately ranked, fading
two-light shadow budget renders twelve 256² cube faces into one 768 × 1024 atlas.
Static/skinned casters share production geometry, coverage and animation. Real
player/enemy firing events drive at most two unshadowed transient lights; the player
light follows the displayed muzzle with wall clipping. New settings and diagnostic
views expose each effect. Atmosphere (step 10) is implemented below.

At 1280 × 720 the new targets add 34.13 MiB on HDR: medium is 207.07 MiB steady /
230.26 MiB baking, with twenty/twenty-three targets. World geometry adds twelve
vertices in two pane batches; collision/navigation remain unchanged. SSR cannot
reflect hidden/offscreen surfaces or transparent panes; glass is thin transmission
without refractive distortion or solid shadow casting. Other native/mobile targets,
WebGL floating-point HDR, context recovery and sustained GPU budgets remain separate.

Validation passes 157 Lua checks and native renderer/HDR/temporal/occlusion,
combat/UI and new reflection/glass/shadow/muzzle-light gates. All 39 supported
stills match every RGB pixel across three independent launches; a 13-image sweep
retains continuous temporal history. The WebGL 2 compatibility path passes 107
stages and pixel checks. The short native street sample rises from 470 to 767 draws
and 109 to 137 µs median render-script CPU with the new effects enabled. Browser
GPU windows measure 6.00/10.56 ms disabled/enabled, with concurrent native capture
work; they are diagnostic samples, not a sustained performance budget. Captures,
comparisons, provenance and cost scope are in `reflections-verified`,
`reflections-validation`, `reflections-review-verified` and
`reflections-browser-verified` under `captures/rendering`.

Step 10 implementation is complete: fixed daylight, sunset and night share the
reference celestial/atmospheric model across direct lighting, sky, filtered IBL,
shadows and fog. A generated 768 × 384 spectral sky lookup includes Rayleigh/Mie/
ozone scattering and a bounded multiple-scatter approximation. Two procedural
cloud decks, a limb-darkened sun, a phased moon and stars complete the sky.
Sky/environment changes publish together and reset temporal history. The pause
menu's Atmosphere tab exposes presets and feature toggles; continuous time and
cloud animation are deliberately deferred until these fixed states are qualified.

A 40-step half-resolution march adds shadowed volumetric air; analytic spectral
transmittance and depth-aware reconstruction preserve foreground edges. The
march uses real cascaded shadow geometry, blended boundaries and cloud visibility.
It follows reflections and precedes world temporal AA; the weapon stays clear.
An enclosed laboratory room verifies a true window opening, mullion and separate
occluder. Market doorways use the same path; opaque upper windows remain opaque.
Analytic fallback, fog/shadow toggles and two diagnostic views support comparison.

Medium HDR at 1280 × 720 is 218.11 MiB steady / 241.29 MiB during loading, with
23 / 26 targets. Fog adds two steady draws (767 → 769 in the street sample).
The native suite passes exact lighting/feature returns, odd resizing, shadowed
shafts and continuous camera history; all 164 Lua checks pass. Native renderer,
HDR, shadows, occlusion, temporal, reflections, combat and UI regressions pass.
Source/capture
provenance, motion and costs are retained in `captures/rendering/atmosphere-*`.
All 46 stills match every RGB pixel across three successful native launches.
The WebGL 2 compatibility path passes 124 stages and the complete pixel gates.
See `README.md` for validation scope, retained failure logs and remaining backend qualification.
The sky bake is synchronous on preset changes; full reference multiscattering,
animated cloud shadows and time-of-day transitions remain future refinements.

Step 11 implementation is complete: shared, footprint-filtered recipes cover
coated/bare metal, polymer, woven/camouflage fabric, rubber and skin. Weapon
and soldier detail stays in mesh/bind space and receives the existing world-space
indirect light, local lights and shadows. Feathered emissive viewmodel flashes
retain independent depth and AA. An isolated linear flash
layer samples weapon depth and resolves into premultiplied radiance, preserving
HDR/encoded storage precision and correct blending on both paths.

Real shot/impact events feed bounded pools of 24 smoke/world-flash quads and 32
surface-aligned impact marks, backed by one shared generated buffer. Soft depth
intersections, receiver depth/normal clipping, fading and restart/pause lifecycle
are implemented. A shared transparent queue sorts effects with glass after world
TAA. The capture catalogue covers all weapon hip/ADS poses, indoor balance,
firing, soft intersections and smoke/glass overlap; frozen actor captures support
soldier review. The Combat menu and automation expose independent feature toggles.
No new render targets are needed; 720p HDR remains 218.11 MiB steady. See README.md
for qualification results, bounded resource costs and compatibility limitations.
All 172 Lua checks pass, and all 56 capture views match every RGB pixel across
three independent native launches. The WebGL 2 compatibility path passes all
143 capture stages and pixel assertions. Physical mobile and sustained GPU budgets
remain subsequent qualification work.

Step 12 implementation adds exposure-scaled multiscale bloom (including muzzle
flashes), bounded GPU exposure adaptation, the generated reference 33³ display
colour grade, restrained luminance sharpening, velocity-based motion blur and
ADS world depth of field. Vignette runs in linear light; grain runs after grading
with a pause-aware presentation clock. Weapon sights and GUI remain independent
of world blur. Frozen captures lock exposure and grain, and native/encoded WebGL
paths share the same treatment. The Photo menu and automation expose all controls.

Low/medium/high photographic tiers use 3/4/5 bloom levels; medium/high add 9/13-tap
optical gathers. Low releases both full-resolution blur targets. At 720p, total
HDR attachment storage is 218.51 / 232.60 / 232.61 MiB. Three alternating short
1024² Chromium/ANGLE Metal samples per tier measure median GPU 8.52 / 8.38 /
11.23 ms and p95 10.30 / 11.73 / 13.73 ms. Medium retains optical effects with a
lower measured GPU cost than high; low is useful for its memory saving. These
samples do not establish sustained combat or physical mobile budgets.

All 177 Lua checks pass, alongside native feature/return pixels, all bloom scales,
bounded exposure, live street/sky adaptation in both directions, pause and Photo
menu controls, odd resize and repeated resource-tier transitions. HDR probes at
three exposures and temporal history/weapon-AA/motion regressions also pass. The
focused WebGL fixture passes 28 stages and pixel gates, including exact street
return. Complete still/motion captures and source fingerprints are retained in
`captures/rendering/photographic-*`; all 56 stills match every RGB pixel across
two independent Metal launches, and five 121-frame sweeps complete. See README.md
for commands and detailed costs.
The implementation is complete, but the final parity/performance gate remains
limited by unfinished reference geometry, unmatched reference lighting, missing
Kaigen captures and unqualified sustained/device budgets.

**7. Synthesize audio at load and rebuild the interface in Defold GUI.**

Initial audio implemented: 76 runtime-generated PCM samples cover three weapons,
reload beats, twelve surface families, movement/damage foley and wind/city ambience.
Budgeted loading, a 24-voice pool, independent audio randomness, distance/panning,
Bullet occlusion, muffled/room gunshot variants, mix headroom and restart/focus
cleanup are wired. Lua and native macOS playback/mixer checks pass, along with a
focused HTML5 check of Web Audio output, movement/enemy combat, restart and room
ambience. Full browser input and physical mobile validation, full source audio
parity and advanced spatial DSP remain outstanding.
The desktop HUD and pause/settings GUI are now implemented: spread/hit feedback,
health and damage direction, compass, a height-filtered generated minimap,
bounded killfeed, audio/display/sensitivity controls and encounter restart.
Pause freezes combat and weapon timelines, suspends audio and isolates menu input;
focus return requires explicit resume. GUI groups preserve layout across aspect
ratios. Settings survive encounter restart within the running session.
Gamepad/touch adapters, saved preferences and browser/mobile UI validation remain
subsequent work. See `README.md` for controls, budgets and validation scope.

Follow Kaigen's approach: synthesize reusable samples during loading, then play them through a bounded voice pool. Defold can create sound-data resources at runtime, so generated WAV data is a viable integration path. [Resource API](https://defold.com/ref/resource/#resource.create_sound_data)

Begin with weapon layers, reloads, surface footsteps, impacts and ambience. Apply distance attenuation and panning in the audio manager. Add runtime-generated muffled/reverberant variants for occlusion and room character. Full HRTF and live convolution would require a separate audio decision.

Recreate the crosshair, hitmarker, ammo, health feedback, compass, minimap, killfeed and pause settings using GUI components. Normalize mouse, gamepad and touch into the same gameplay commands.

**Original milestones mapped to current status (2026-10-15)**

| Milestone | Current status | Remaining completion check |
|---|---|---|
| 1. Technical foundation | Implementation complete; platform qualification open | Representative native, full browser and physical mobile scenarios; remaining step 19 |
| 2. Playable street block | Complete for the existing desktop slice; expanded to three weapons, two enterable buildings and six enemies | Preserve its regression scenarios as the map expands |
| 3. World and movement | Partial: excerpt and core traversal complete | Full map, recipes, dressing, vaulting and camera feel; remaining steps 2–5 |
| 4. Combat parity | Partial: weapons and basic squad combat complete | Health, detailed weapon/soldier behavior, regional damage, ragdolls, tactics and grenades; remaining steps 6–12 |
| 5. Presentation | Partial: core renderer, audio and HUD implemented | Content/FX, animated atmosphere, audio, HUD/input and matched reference views; remaining steps 1, 3–4, 7, 9 and 13–17 |
| 6. Optimization and advanced effects | Partial: major render effects and component quality tiers implemented | Whole-game presets, adaptive quality, sustained performance and platform gates; remaining steps 18–19 |

The [project configuration](/Users/bjornritzl/projects/defold-claude-of-duty/game.project) now establishes 3D physics, metre-based units and the source game's movement gravity. The Automation Bridge setup supports traversal scripts, combat scenarios and screenshot capture.

For validation, carry over the original named camera shots and fixed seeds. Compare cross-engine images for composition and appearance; reserve exact image regression checks for controlled runs within a backend. Measure loading time, memory, draw calls and p95/p99 frame times during movement and firing.

The original street-block prototype is implemented. Continue with the remaining work in the ordered backlog above; retain these earlier measurements as historical evidence rather than current full-map or all-platform budgets.
