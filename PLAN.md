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
