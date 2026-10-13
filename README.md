# Defold Claude of Duty

Runtime-generated port targeting Defold 1.14.0. See [PLAN.md](PLAN.md).

The first plan step is implemented: a gameplay controller, six subsystem modules,
120 Hz fixed simulation, metre-based 3D physics with gravity -20.6 m/s², buffered
input, gameplay notifications, centralized damage, and separate camera/HUD
presentation. The first world slice is also generated at runtime: a 28-metre
market street, pavements, W2 with one open shop room, and the opposing E2 facade.
A swept kinematic capsule now supports walking, sprinting, tactical sprint,
sliding, mantling, leaning, jumping, crouching, prone movement, stairs and slopes.
The M4A1, MPX-9 and P-19 now have fixed-tick fire control, projectile ballistics,
reloads and generated viewmodels in an isolated render pass. One runtime-generated,
25-bone soldier now patrols the street, detects and pursues the player, fires
physical rounds and dies. GPU-generated surface maps, shared material lighting,
animated sun shadows, a procedural sky, height fog, tone mapping and bloom are
implemented. A runtime-generated sound bank now supplies weapon fire, reloads,
surface footsteps/impacts, movement foley and ambience through a bounded spatial
audio mixer.
The combat HUD now includes a compass, generated minimap, damage direction,
health bar and killfeed. Escape opens a pause menu with audio, display and
mouse controls; focus loss also pauses the encounter.

## Run and validate

Open `game.project` in Defold 1.14.0, fetch libraries, then build and run.
The existing Automation Bridge dependency supports native smoke checks.
Run the engine-independent regression suite from the repository root:

```sh
lua tests/runtime_test.lua
lua tests/world_test.lua
lua tests/movement_test.lua
lua tests/weapons_test.lua
lua tests/ai_test.lua
lua tests/renderer_test.lua
lua tests/audio_test.lua
lua tests/ui_test.lua
```

With the project open in Defold, the native smoke test builds the game, checks
world loading, collision dimensions, doorway clearance, navigation, inspection
views, timing, input, damage and HUD updates, then closes the engine it launched:

```sh
PYTHONPATH=automation-bridge-python python3 tests/smoke.py
PYTHONPATH=automation-bridge-python python3 tests/movement_smoke.py
PYTHONPATH=automation-bridge-python python3 tests/movement_features_smoke.py
PYTHONPATH=automation-bridge-python python3 tests/weapons_smoke.py
PYTHONPATH=automation-bridge-python python3 tests/ai_smoke.py
# Requires Pillow for GPU pixel assertions:
PYTHONPATH=automation-bridge-python python3 tests/renderer_smoke.py
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
a restart prompt. A four-entry killfeed records confirmed deaths through combat
notifications, expires after six active seconds and clears on encounter restart.

The compass uses north = world -Z and east = +X. The north-up minimap follows the
player over a 44-metre square, drawing the generated world's collision footprints
and a rotated player marker. Rectangles are clipped to the map and the player's
floor height, so the shop's roof does not fill its accessible interior. The
current slice supplies 36 rectangles; the GUI bounds this to 128 for larger maps.
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

One soldier patrols the far end of the street. Approach it to trigger detection
and combat. **9** restarts the encounter with full player/enemy health, fresh
weapons and ammunition. Inspection cameras pause enemy simulation. The separate
world/movement/weapon smoke suites explicitly pause AI to isolate their fixtures.

## Procedural soldier and combat

`game/ai/rig.lua` retains the reference's 25 joint names, hierarchy and metre
proportions, rotating the source's +Z-facing carry pose into this project's -Z
convention. The bind axes are identity rotations; they do not yet reproduce the
reference ragdoll joint frames. `geometry.lua` generates cloth limbs, helmet,
goggles, carrier, pouches, boots, gloves and a simplified carried rifle. The mesh
has 7,140 vertices and 514,080 bytes of float streams: position, normal, colour,
four joint indices and four normalized skin weights. Some vertices blend two
joints; rigid equipment follows one. No model or animation is imported.

`soldiers/soldier.vp` performs linear blend skinning with 25 matrix uniforms.
The palette is 1,600 bytes, uploaded with 25 indexed `go.set` calls per actor per
presentation frame. One shared generated buffer serves replacement instances;
each live soldier uses one mesh, one movement capsule and seven hit-volume GOs.
Conservative bounds include the supported animations and death collapse. The
fragment shader supplies procedural camouflage, with the world's sun, ambient
light and fog. `skinning.glsl` is shared by the colour and animated sun shadow
passes introduced in renderer step 6.

Idle breathing, distance-driven walking, upper-body aiming, recoil and a bounded
0.85-second death collapse are evaluated in Lua. Simulation poses advance at
120 Hz. Presentation interpolates position, heading and pose parameters without
changing collision transforms. This is a deliberately simplified animation
prototype: runtime foot/hand IK, source clip parity and physics ragdolls remain
later work. Death disables hit volumes and leaves one visible corpse until restart.

`game/systems/ai.lua` owns the enemy and a separate bounded projectile pool. A
patrol detects a visible player within 14 metres and a 130-degree field of view,
after four perception checks at roughly 10 Hz. An alerted actor remembers the
last seen point for five seconds and can see up to 24 metres. It pursues until
within ten metres with a clear muzzle path, then aims and fires one 400 m/s round
every 0.55 seconds. A round starts at the animated rifle muzzle, uses existing
travel/drop/penetration code and queries the actual player capsule. Health still
changes only through `game/combat.lua`, on the following fixed tick. Enemy fire
has its own seeded random stream. Dead players cannot be reacquired or fired on.

Patrol/pursuit routes use shortest paths over the existing authored, layered
navigation graph, including temporary start/goal links. Native queries validate
floor support and capsule clearance before accepting a connection. Movement then
uses the same swept capsule controller as the player, including kerb step-up,
wall sliding and overlap recovery. Routes are refreshed for moved targets or
after one second. Unreachable goals leave the soldier in place and retry; this
is not a generated navmesh or a squad navigation implementation. The movement
capsule collides with the world; actor-to-actor movement blocking is not implemented.

Head, chest, hips, thighs and shins have kinematic Bullet boxes transformed by
the same skeleton as the mesh. Projectile thickness is measured in each box's
rotated local frame. Head hits retain the existing 2× multiplier; overlapping
body volumes still submit at most one hit per actor per round. Limbs use simple
proxies; arms, hands and equipment do not have separate damage volumes yet.

The 12 soldier Lua tests check mesh winding and weights, bind/deformed poses,
animated bounds, rotated hit volumes, headshot/duplicate-damage rules, routing,
perception, occlusion, death/reset and 30/60/144-FPS equivalence. Native Metal
validation checks patrol, actual head/body shots, return fire, wall occlusion,
shop entry, repeated replacement, keyboard restart and clean teardown. The
snapshot reports Lua-side palette upload time and AI tick cost; these are not
GPU timings or whole-frame performance measurements. A debug `wasm-web` bundle
also passed a manual WebGL 2 browser check for world/soldier rendering, walking,
enemy return fire, player death and key-9 restart, with no new console errors.
That check caught and fixed a GLSL ES reserved-word error accepted by Metal.
The browser check is narrower than the native automated suites; physical mobile
devices and full browser regression coverage remain untested.

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

`mantle.lua` probes only on a forward jump request (held requests may retry at
20 Hz). Ledges must be higher than the current step limit and no more than
1.85 m above the current feet. An airborne catch therefore has additional jump
reach. A downward probe confirms enough landing depth; the full up/forward/
settle path is checked with the standing capsule, then crouched if necessary.
The 0.34–0.82-second climb is swept again every fixed tick. New obstructions,
death or inspection cancel it at the current position, never at an unchecked
destination. Thin railings without a supported landing are rejected; automatic
vaulting is not part of this implementation.

`lean.lua` smooths a 0.34 m camera offset and 13° roll without moving the capsule.
A 0.17 m sphere sweep limits the offset, both in fixed updates and after camera
interpolation. New obstructions retract it immediately. Stance eye interpolation
is capped by the current capsule height when entering low headroom.

The Lua movement tests cover jump timing, clearance, look, loading and equivalent
simulation at 30/60/144 presentation FPS. The native movement test builds an
optional course and drives input through actual Defold fixed ticks to check
speed, corners, thin-wall sweeps, stairs, slopes, ceilings, door widths and
entry into W2. The feature suite covers tactical sprint, slide duration and
jump exits, valid/invalid mantle routes, crouch-only landings, lean clearance
and cancellation on death. Native validation currently targets macOS/Metal;
full browser/mobile traversal-suite validation remains a later milestone.

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
recipes and source-scale attachment points. These are simplified models, not
full copies of every reference mesh detail. The three weapons contain 11,568
vertices across 24 independently transformable parts, including hands, reticles
and muzzle flashes (462,720 bytes of vertex streams before resource overhead).
Twenty-four pooled effect meshes provide short-lived impact particles, cases and
tracers; they have no debris physics. All generated buffers and game objects are
released on teardown. Surface audio routing now selects generated impact samples;
weapon fire and reload beats also drive the audio system described below.

`render/game.render_script` draws the viewmodel with its own camera into an RGBA
colour target with a separate depth attachment. Its lighting coordinates are
transformed through the world camera, so the same sun, shadows, environment and
room light illuminate the weapon and world. The weapon receives no world fog or
world bloom; both layers go through one exposure and tone-mapping function before
GUI. The reticle appears only in ADS. Weapon vertex alpha stores metalness while
the shader writes opaque coverage. Temporal effects remain later work.

The 18 weapon Lua tests cover timing, inputs, reload interruptions, deterministic
spread/recoil, geometry bounds/winding and continuous collision/penetration.
The native weapon suite uses real input bindings, fixed ticks and Bullet targets,
checks damage through wood versus concrete and at a muzzle-obstructing wall,
and captures hip/ADS/reload/inspection views. Native validation targets
macOS/Metal; full browser/mobile weapon-suite validation remains outstanding.

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
shell, impact and tracer notifications. Audio consumes notifications without
applying damage or advancing any gameplay random stream. Future systems supply
their remaining event producers.

Actor, camera, generated mesh batches and structural collision objects are wired.
World batches and collision objects belong to the world module; enemy game objects belong to AI.
Each system must release its generated Defold resources in `final`.

## Generated world

`game/world/layout.lua` is the authored description. It retains the reference's
9-metre road, 6.5-metre building line, 0.145-metre pavement and W2/E2 footprints.
This is an unrotated excerpt, with a simplified W2 interior and closed upper
floors. It is not the full map or the complete original building recipe set.

`recipes.lua` emits boxes from that description. Each structural box produces
both visual triangles and a collision descriptor with a surface identifier.
The shop front consists of separate side walls and a lintel, leaving a genuine
2.8 × 2.65-metre opening. Small window trim, shelves, canopy fabric and produce
are visual detail; tables, crates, walls and floors have simple solid proxies.

`generator.lua` merges geometry by material and 16-metre spatial bucket, capped
at 64 boxes per mesh upload. Every batch carries explicit AABB buffer metadata
for Defold's frustum culling. There are no game objects per decorative piece.
The initial slice generates 232 boxes, 39 mesh batches, 8,352 vertices and 36
collision objects. Vertex streams occupy 334,080 bytes (CPU/GPU resource overhead
is additional; the batch count is not a measured per-frame draw-call count).

Loading advances through geometry, mesh uploads, collision creation and a
settling frame before `ready`. Geometry handles at most 24 boxes per frame;
collision creation at most eight; uploads at most one bounded batch. A soft
2 ms CPU deadline is checked between geometry/collision jobs. A single upload
is indivisible. `world.snapshot` reports total CPU work and the peak loading
update; it excludes shader compilation and other engine work outside these calls.
Factory objects and generated buffer resource references are released on teardown.

Seeded decoration, spawn and weapon streams are independent. The current spawn
points are authored. Changing loading budgets or decorative detail cannot move
collision, spawn points, or advance the gameplay random streams.

Metadata includes floor rectangles with heights and layers, navigation nodes,
bidirectional connections (including the kerb step and doorway), cover candidates,
lights, spawn points and minimap rectangles with vertical bounds. Native
validation checks floor support and clear connection centrelines. These are
navigation inputs, not a finished navmesh or proof of every route's clearance.
The movement suite additionally checks capsule traversal from the street over
the kerb and through the doorway into W2.

Generated world materials now sample runtime GPU atlases and receive the lighting,
shadows and height fog described below. The room light is sourced from the same
world metadata and clipped to its authored interior bounds.

## Generated materials and rendering

The renderer owns nine targets. During the first nine rendered frames it bakes
one 1280 × 256 atlas per frame (albedo variation, tangent-space normals, and
roughness/metalness/cavity), then one 64 × 64 sky cubemap face per frame. Each atlas
contains five 256² surface tiles with periodic padding. Reduced recipes adapt the
reference's plaster mottling, asphalt aggregate, wood fibres, worn metal and cloth
weave; these are not a complete port of its high-resolution material library.
World-space projection keeps the generated geometry independent of UV assets.
The GPU bakes never advance gameplay random streams and do not repeat on resize
or encounter restart. Context restoration schedules the nine jobs again.

World geometry, the soldier and weapons share GGX direct lighting, ambient light,
approximate sky reflections and up to four authored point lights. The current
room light has warm radiance, finite attenuation and interior bounds to prevent
lighting across exterior walls. Props do not occlude this local light. The soldier
retains procedural camouflage; weapon vertex colours now carry metalness.

A 1024² shadow target covers a fixed 64-metre square around the initial street
block. Static batches and the soldier use separate shadow materials; the latter
shares the colour pass's 25-bone palette and skinning function. Shadow depth is
packed in two RGBA8 channels and compared with nine nearest samples, a depth bias
and a normal offset. Out-of-map receivers are unshadowed; the remote optional
traversal/firing fixtures are not guaranteed shadow coverage. Cascades, local-light shadows
and screen-space ambient occlusion remain future work.

Pass order is sun shadow → sky/world → isolated weapon → two quarter-resolution
bloom passes → composition/tone mapping → GUI. Height fog integrates an exponential
height density along the eye ray. The world and weapon use square-root encoded
0..8 radiance in RGBA8, with subtle dithering, so the pipeline needs no floating
point colour-buffer extension. The final pass decodes the layers, applies one
exposure and an ACES-style curve, then converts to display gamma. Bloom affects
only the world; GUI stays outside exposure, fog and bloom. This is bounded HDR,
not an unbounded floating-point pipeline. Environment reflections currently use
an analytic broadening approximation rather than prefiltered roughness mipmaps;
the material atlas also has no mip chain yet. `game.project` sets the default
GLSL ES float precision to `highp` for noise, packed shadows and lighting. Using
the project setting also keeps precision declarations ahead of Defold's generated
fragment output in WebGL shaders.

At a 1920 × 1280 backbuffer (the default window on a 2× display), target storage
is approximately 50.5 MiB, excluding driver overhead and generated meshes. This
includes conservatively budgeted 32-bit depth attachments. At 960 × 640 it is
approximately 21.5 MiB. Resize updates the four screen-dependent targets while
retaining the atlas, cubemap and shadow targets. Zero-sized windows skip rendering;
finalization deletes every target.

`renderer.snapshot` reports bake jobs, target dimensions/bytes, local-light count,
shadow frames and active settings. `renderer.configure` accepts booleans
`shadows`, `normal_maps`, `local_lights`, `fog`, `bloom`; numeric `exposure` in
0.25..4; and `view` equal to `scene`, `albedo`, `normals`, `material`, `shadow` or
`environment`. Configuration applies on the next render message dispatch, so tests
wait for the snapshot to reflect it. All controls affect presentation only.

The renderer Lua suite checks loading budgets, pass order, feedback avoidance,
resize/minimize behavior, effect toggles, context-rebake scheduling and teardown.
The native suite checks actual GPU atlas channels, visible shadow/normal/light/
bloom contributions, animated shadow collapse, exposure, hip/ADS views and resize,
with review images in `build/renderer-validation`. All 90 Lua checks and the
native renderer, weapons, soldier and framework suites pass on macOS/Metal. The
HTML5 debug bundle also passes a manual WebGL 2 check of street/room lighting,
shadows, sky, movement, encounter restart and the separate weapon pass, with no
shader/runtime errors after loading. That browser check does not replace the
native pixel suite. Hardware context-loss recovery, physical mobile devices,
full source visual parity and sustained combat GPU performance remain separate
validation work.

## Generated audio

`game/audio/synth.lua` generates 76 mono PCM16 WAV samples at 22,050 Hz during
loading. The bank occupies 1,627,520 bytes (about 1.55 MiB), excluding engine
resource overhead and temporary synthesis buffers. The only bundled WAV is a
32-frame silent placeholder required by Defold sound components. Audible samples
are created with [`resource.create_sound_data`](https://defold.com/ref/resource/#resource.create_sound_data)
and released on teardown; no native audio extension or imported recording is used.

The rifle, SMG and pistol combine a pressure transient, swept low body, noisy crack,
tail and delayed mechanical tick, with source-derived profile tuning. Each has
three deterministic variations and dry, room-reflection and low-pass muffled
versions. Twelve surface families supply impact and alternating-footstep samples.
Reload sounds follow the actual magazine/bolt beats, including cancellation;
dry triggers, casing ejection, landing, stance/slide/mantle cloth and player damage
also have cues. Player shots stay centred; enemy shots and impacts use world
positions. Casing audio accompanies ejection, since casings have no physics.

Synthesis advances in 1,024-sample chunks, at most 8,192 samples per frame, with a
soft 2 ms deadline checked between chunks. Final WAV concatenation and resource
upload are indivisible. Gameplay waits at the world's final loading phase until
the bank is ready. `audio.snapshot` reports measured total/peak CPU loading work;
the native validation run took roughly 375 ms total, spread over frames, with a
3.2 ms peak job. Loading rate and sound variation never affect world generation,
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
surface. `world.view` takes `{name = "street" | "shop" | "room"}`.
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
