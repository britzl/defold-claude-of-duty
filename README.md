# Defold Claude of Duty

Runtime-generated port targeting Defold 1.14.0. See [PLAN.md](PLAN.md).

The first plan step is implemented: a gameplay controller, six subsystem modules,
120 Hz fixed simulation, metre-based 3D physics with gravity -20.6 m/s², buffered
input, gameplay notifications, centralized damage, and separate camera/HUD
presentation. The first world slice is also generated at runtime: a 50-metre
market street, pavements, a two-storey W2 shop/apartment, and an enterable
three-storey E2 shop with two upper apartments. Closed W1/W3 shopfronts frame
a west courtyard and alley linked by a rear lane around W2.
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
lua tests/squads_test.lua
lua tests/suppression_test.lua
lua tests/renderer_test.lua
lua tests/shadows_test.lua
lua tests/temporal_test.lua
lua tests/local_lights_test.lua
lua tests/surface_atlas_test.lua
lua tests/visible_faces_test.lua
lua tests/weathering_test.lua
lua tests/render_capture_test.lua
lua tests/audio_test.lua
lua tests/ui_test.lua
```

With the project open in Defold, the native smoke test builds the game, checks
world loading, collision dimensions, doorway clearance, navigation, inspection
views, timing, input, damage and HUD updates, then closes the engine it launched:

```sh
PYTHONPATH=automation-bridge-python python3 tests/smoke.py
PYTHONPATH=automation-bridge-python python3 tests/building_smoke.py
PYTHONPATH=automation-bridge-python python3 tests/market_smoke.py
PYTHONPATH=automation-bridge-python python3 tests/movement_smoke.py
PYTHONPATH=automation-bridge-python python3 tests/movement_features_smoke.py
PYTHONPATH=automation-bridge-python python3 tests/weapons_smoke.py
PYTHONPATH=automation-bridge-python python3 tests/ai_smoke.py
PYTHONPATH=automation-bridge-python python3 tests/squads_smoke.py
PYTHONPATH=automation-bridge-python python3 tests/suppression_smoke.py
# Requires Pillow for GPU pixel assertions:
PYTHONPATH=automation-bridge-python python3 tests/renderer_smoke.py
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
(current colour, current prepass and previous prepass), totalling 4,800 bytes
and 75 indexed `go.set` calls plus one previous-root matrix per actor per
presentation frame. One shared generated buffer serves all six soldiers and
replacement instances; each live soldier uses two mesh components on one GO, one movement capsule and
seven hit-volume GOs. Conservative bounds include the supported animations and
death collapse. The fragment shader supplies procedural camouflage, with the
world's sun, ambient light and fog. `skinning.glsl` is shared by the colour and
animated sun shadow passes introduced in renderer step 6.

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
accepted static-world graph edges are cached for the encounter while endpoint
connections are always probed. Unreachable paths retry at most once per second.
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

Head, chest, hips, thighs and shins have kinematic Bullet boxes transformed by
the same skeleton as the mesh. Projectile thickness is measured in each box's
rotated local frame. Head hits retain the existing 2× multiplier; overlapping
body volumes still submit at most one hit per actor per round. Limbs use simple
proxies; arms, hands and equipment do not have separate damage volumes yet.

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
images are saved in `build/squad-validation`. The six soldiers use 54 game
objects, 42 live hit volumes and one shared 0.49 MiB mesh buffer; the existing
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
The six actors still use 54 objects, 42 hit volumes and one shared mesh buffer.
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
shell, impact, travelled-segment and tracer notifications. Impact and segment
notifications share an opaque per-round token for suppression deduplication.
Audio consumes notifications without
applying damage or advancing any gameplay random stream. Future systems supply
their remaining event producers.

Actor, camera, generated mesh batches and structural collision objects are wired.
World batches and collision objects belong to the world module; enemy game objects belong to AI.
Each system must release its generated Defold resources in `final`.

## Generated world

`game/world/layout.lua` is the authored description. It retains the reference's
9-metre road, 6.5-metre building line, 0.145-metre pavement and W1/W2/W3/E2 footprints.
This is an unrotated excerpt. The road spans z=-28..22. W1 and W3 retain the
reference footprints and use closed shopfronts; their setbacks, balconies and W3
ruin details remain future work.
The west courtyard and alley on opposite sides of W2 adapt the reference
passages to meet the building edges. A four-metre rear lane joins them at
x=-25.5..-21.5, forming a second route between the street junctions at z=7.5 and
z=-10. Yard walls close the outer edges. `layout.ground`, `routes`, `walls` and
`covers` describe the extension; tiled ground and cover solids feed collision,
surface audio and minimap output. Two low barriers and a rear crate provide cover
without obstructing the walking route. Seven cover candidates have supported,
capsule-clear positions; squad AI selects and exclusively claims protected
positions with a firing lane.

W2 has an open ground-floor shop and a furnished upper apartment; E2 has a shop
and two furnished upper apartments. This is not the full map or the complete
original building recipe set.

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

`generator.lua` merges geometry by material and 16-metre spatial bucket, capped
at 64 boxes per mesh upload. Every batch carries explicit AABB buffer metadata
for Defold's frustum culling. There are no game objects per decorative piece.
Slabs own the top of each storey, and walls/trim use butt joints at corners.
`visible_faces.lua` subtracts buried surfaces and gives coincident outward faces
one owner before triangulation. This removes depth ties at slab edges, trim
undersides and kerbs without changing collision proxies. The slice generates
519 boxes, 77 mesh batches, 36,552 vertices and 190
collision objects. Vertex streams occupy 1,462,080 bytes (CPU/GPU resource overhead
is additional; the batch count is not a measured per-frame draw-call count).

Loading advances through geometry, mesh uploads, collision creation and a
settling frame before `ready`. Geometry collects recipes, clips faces and indexes shared edge endpoints, then
meshes them, handling at most 24 jobs per frame across these three stages;
collision creation at most eight; uploads at most one bounded batch. A soft
2 ms CPU deadline is checked between geometry/collision jobs. A single upload
is indivisible. `world.snapshot` reports total CPU work and the peak loading
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
Catalogue version 9 expands the repeatability gate to 39 supported shots and retains the 0.1–500 m world clip
range; the 0.1 m near plane improves depth precision while remaining inside the
player's wall clearance. The separate weapon clip range is unchanged.

The catalogue in `game/render/capture.lua` has street, interior, detail, courtyard,
weapon, ADS and laboratory captures, plus fifteen material close-ups, near/mid/far façade views and a grazing
road view. Sunset and night are explicitly unsupported
until rendering step 10; no substitute daylight images are written. Current
lighting is fixed daylight, not a matched 16:30 astronomical configuration.
The generated laboratory has fifteen surface panels, a floor, a corner with crates,
a table and two sphere rows: rear dielectric, front metal, with roughness
0.08/0.25/0.5/0.75/1 from left to right. It uses the production world shader and
shadow pass; uniform sphere parameters isolate lighting from the texture recipes.
Its 31 meshes are released on exit; the shadow fixtures include a perforated
panel and a remote floor/occluders 160 m from the street. The reflection fixture
plate shares visibility clipping and edge stitching with its box and floor,
avoiding depth ties at the reflected contact.

The optional laboratory, grazing-road, weathered-façade, shadow-distance and
cutout-shadow sweeps each contain 121 frame-addressed camera samples at 30 FPS. Screenshot transport never advances gameplay or the sweep;
`capture.frame` explicitly selects each pose. Their MP4s are for visual stability
review and do not measure real-time frame pacing.

Capture the local Three.js source with its own deterministic 90-frame shutter:

```sh
# In the reference checkout first: npm ci --ignore-scripts
node tools/capture_reference.mjs --source=/path/to/Claude-of-Duty-main --baseline=/path/to/defold/manifest.json
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
Kaigen reference captures and a corresponding reference laboratory remain pending:
the local Kaigen download does not include its closed-beta engine.

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
Weapon/soldier material expansion remains step 11.

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

Loading remains budgeted: expensive recipe draws run individually and up to eight
copy/filter jobs run per frame. The environment is one complete 128-sample bake
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

Static/capture batches and animated soldiers draw into each cascade with their
own light frustum. The colour and shadow passes share the soldier's 25-bone
skinning and the world's procedural binary-coverage function. Vertex alpha of
one stays solid; lower world alpha opens circular holes on a 30 cm grid. Soldier
alpha remains camouflage weight. A laboratory panel checks matching visible
holes and projected shadows. The complete atlas clears once per frame, including
when shadows are disabled; all four tiles draw in that same render pass so tile
GPUs retain earlier cascades.

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
→ bilateral resolve → sky/world/material data → reflections → temporal resolve
→ separate weapon AA → glass accumulation/composition → two quarter-resolution
bloom passes → composition/tone mapping → GUI. Height fog integrates an exponential
height density along the eye ray. Rendering step 2 enables linear RGBA16F for
scene, weapon, bloom and environment on Metal. Radiance interpolation and blending
remain linear and are no longer limited to 0..8. Authored vertex colours use the
piecewise sRGB transfer function; generated atlas values are linear albedo.
The final pass composites world/weapon light, applies one fixed exposure and the
references' neutral AgX curve, then performs one accurate sRGB display conversion
with deterministic 8-bit dithering. Bloom affects only the world; GUI stays
outside exposure, fog and bloom. The reference look/grade is deferred to step 12.

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
shadow submissions, temporal history/reset status and AA passes, plus bake
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
also accepts `--browser=/path/to/chromium` to reuse an installed executable. The fixture exercises all recipes,
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
uploads 76 matrix properties per actor; physical mobile and other native
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
