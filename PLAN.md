# Defold port implementation plan

Date: 2026-10-13. Target engine: Defold 1.14.0.

Implement a runtime-generated Defold port of Claude of Duty, with Lua gameplay systems, a custom render pipeline, and a small portable native extension where geometry generation or audio synthesis needs more performance. The same implementation should serve Defold's platforms, with adaptable input and graphics budgets.

The result should retain the recognizable market street, procedural soldiers, three weapons, movement, and combat feedback. Preserve runtime generation wherever practical rather than making pre-baked art and audio the default.

This plan is based on a source-level review of the Three.js and Kaigen versions. Performance comparisons have not been run. The local Kaigen download lacks its engine checkout, so running that version requires the external engine.

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

Initial slice implemented: a 28-metre street using W2/E2 footprints, one enterable
shop room, merged runtime meshes with culling bounds, matching static Bullet
boxes, and navigation/cover/spawn/light/minimap metadata. Loading uses bounded
jobs and separate random streams. Street, shopfront and room inspection cameras
are available on keys 1–3. Capsule traversal now verifies the street-to-room
route. W2 has since been expanded into a complete two-storey shop/apartment with
sixteen steps, a true floor opening, guards, upper partitions/open doorways,
furniture, floor-specific minimap geometry and room lighting/audio bounds. Its
30-node layered graph shares dimensions with the stair/slab recipe; native checks
cover player ascent/descent and enemy routes/pursuit between floors. This is the
first building increment toward milestone 3. The full layout and additional
building recipes remain subsequent work.
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
pass added in step 6; runtime IK, ragdolls, squads and source visual parity are still
subsequent work. See `README.md` for costs, controls and validation scope.

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
asphalt, wood, metal and cloth; a six-face procedural sky environment is generated
one face per frame. World, soldier and weapon share roughness/metalness lighting,
sunlight, ambient/reflection terms and up to four bounded local lights. A 1024²
sun shadow map uses the same animated soldier skinning as the colour pass.
Height fog, quarter-resolution bloom, shared tone mapping and an isolated weapon
colour/depth pass precede the GUI. Diagnostic views and effect toggles are exposed
through the Automation Bridge. The 72 Lua tests, native macOS/Metal renderer and
combat smoke suites pass, as does a focused HTML5/WebGL 2 visual/input check;
physical mobile validation is still outstanding. Surface recipes and environment lighting are
bounded approximations; full material parity, mip/roughness filtering, local-light
shadows, cascades, ambient occlusion and temporal effects remain later stages.
See `README.md` for resource budgets and validation scope.

Port the procedural surface functions into Defold shaders that render albedo, normal and packed material maps during loading. Preserve texture generation rather than replacing it with exported images.

The initial lighting pipeline should contain:

- Sunlight, ambient/environment illumination and a bounded set of local lights.
- Normal mapping and roughness/metalness shading.
- Shadow maps.
- Procedural sky and height fog.
- Separate weapon rendering.
- Tone mapping, modest bloom and the HUD.

Defold exposes PBR material data, but its documentation explicitly distinguishes that from providing a complete built-in PBR lighting model. Lighting and reflections still need shader implementation. [PBR documentation](https://defold.com/manuals/physically-based-rendering/)

Use 1.14.0 cubemap targets for environment generation, with updates spread over frames. Roughness filtering remains additional work.

Add ambient occlusion and better shadows next. Treat TAA, motion vectors, SSR, volumetric lighting and motion blur as later rendering milestones. The source's full pipeline is substantial enough to be a project within the port.

Establish consistent world and weapon lighting early. The Three.js README's reported viewmodel exposure problems are a useful warning against accumulating compensating material adjustments.

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

**Implementation milestones**

| Milestone | Deliverable | Completion check |
|---|---|---|
| 1. Technical foundation | Generated geometry and material, capsule movement, generated sound, procedural skinned character, separate weapon pass | These paths work in representative native, browser and mobile builds |
| 2. Playable street block | One detailed block, one enterable building, one rifle and one enemy | Move, aim, shoot, reload, take damage and respawn |
| 3. World and movement | Full layout, interiors, stairs, props, slide, mantle and lean | Traversal course passes; visual geometry and collision agree |
| 4. Combat parity | Three weapons, six enemies, navigation, cover, squads and penetration | Repeatable combat scenarios complete without stuck AI or duplicate damage |
| 5. Presentation | Procedural materials, lighting, sky, shadows, FX, audio and complete HUD | Matched reference views establish the visual quality |
| 6. Optimization and advanced effects | Quality presets, loading improvements, selected advanced rendering | Frame-time and memory targets hold during sustained combat |

The first milestone should resolve the expensive uncertainties before translating thousands of lines of world detail.

The [project configuration](/Users/bjornritzl/projects/defold-claude-of-duty/game.project) now establishes 3D physics, metre-based units and the source game's movement gravity. The Automation Bridge setup supports traversal scripts, combat scenarios and screenshot capture.

For validation, carry over the original named camera shots and fixed seeds. Compare cross-engine images for composition and appearance; reserve exact image regression checks for controlled runs within a backend. Measure loading time, memory, draw calls and p95/p99 frame times during movement and firing.

The first concrete implementation should be a generated street block with one room, one rifle and one procedural soldier—backed by the skinning, collision and audio prototypes above. That establishes whether the proposed architecture delivers the game's feel and runtime-generated identity before expanding to the entire map.
