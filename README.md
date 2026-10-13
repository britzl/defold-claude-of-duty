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
reloads and generated viewmodels in an isolated render pass. Soldiers and
synthesized audio remain subsequent work.

## Run and validate

Open `game.project` in Defold 1.14.0, fetch libraries, then build and run.
The existing Automation Bridge dependency supports native smoke checks.
Run the engine-independent regression suite from the repository root:

```sh
lua tests/runtime_test.lua
lua tests/world_test.lua
lua tests/movement_test.lua
lua tests/weapons_test.lua
```

With the project open in Defold, the native smoke test builds the game, checks
world loading, collision dimensions, doorway clearance, navigation, inspection
views, timing, input, damage and HUD updates, then closes the engine it launched:

```sh
PYTHONPATH=automation-bridge-python python3 tests/smoke.py
PYTHONPATH=automation-bridge-python python3 tests/movement_smoke.py
PYTHONPATH=automation-bridge-python python3 tests/movement_features_smoke.py
PYTHONPATH=automation-bridge-python python3 tests/weapons_smoke.py
```

The game starts in first person. **W/A/S/D** moves, **Shift** sprints, **Space**
jumps, **Ctrl** holds crouch, and **Z** holds prone. Click to capture the mouse
for looking; **Esc** releases it. Holding right mouse aims down the weapon sight
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
audio synthesis remains separate work.

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
browser/mobile validation remains a later milestone.

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
released on teardown. Surface audio routing is ready for synthesized playback
in step 7; there is no weapon sound playback yet.

`render/game.render_script` explicitly selects the world camera, then draws the
viewmodel with its own camera into an RGBA target with a separate depth
attachment. The transparent weapon target is composited before GUI. It resizes
with the window and is released on shutdown. Weapon materials use the same sun
and ambient colours as the world, with camera-relative sunlight, and receive no
world fog. The reticle appears only in ADS. Future world post effects can run
before weapon compositing. PBR and temporal effects remain renderer milestones.

The 18 weapon Lua tests cover timing, inputs, reload interruptions, deterministic
spread/recoil, geometry bounds/winding and continuous collision/penetration.
The native weapon suite uses real input bindings, fixed ticks and Bullet targets,
checks damage through wood versus concrete and at a muzzle-obstructing wall,
and captures hip/ADS/reload/inspection views. Native validation targets
macOS/Metal; browser/mobile runtime validation remains outstanding.

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
positions. `late_update` applies the camera transform and sends changed HUD data
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
FX ignores player damage for hitmarkers. Weapons produce fire, reload, shell,
impact and tracer notifications; surface audio keys do not synthesize or play
sound. Future systems supply their remaining event producers.

Actor, camera, generated mesh batches and structural collision objects are wired.
World batches and collision objects belong to the world module; future enemy game objects belong to AI.
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

The initial material uses procedural grain, directional/ambient lighting and
distance fog in the custom renderer's world pass. Local lights are metadata for the
later renderer; PBR, shadow maps, generated material textures and the full render
pipeline remain in step 6. Separate weapon rendering is already implemented.

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

Discover commands with `game.application_catalog(kind="command")`. For example:

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
