# Defold Claude of Duty

Runtime-generated port targeting Defold 1.14.0. See [PLAN.md](PLAN.md).

The first plan step is implemented: a gameplay controller, six subsystem modules,
120 Hz fixed simulation, metre-based 3D physics with gravity -20.6 m/s², buffered
input, gameplay notifications, centralized damage, and separate camera/HUD
presentation. The first world slice is also generated at runtime: a 28-metre
market street, pavements, W2 with one open shop room, and the opposing E2 facade.
A swept kinematic capsule now supports walking, sprinting, jumping, crouching,
prone movement, stairs and slopes. Weapons, soldiers and synthesized audio remain
subsequent work.

## Run and validate

Open `game.project` in Defold 1.14.0, fetch libraries, then build and run.
The existing Automation Bridge dependency supports native smoke checks.
Run the engine-independent regression suite from the repository root:

```sh
lua tests/runtime_test.lua
lua tests/world_test.lua
lua tests/movement_test.lua
```

With the project open in Defold, the native smoke test builds the game, checks
world loading, collision dimensions, doorway clearance, navigation, inspection
views, timing, input, damage and HUD updates, then closes the engine it launched:

```sh
PYTHONPATH=automation-bridge-python python3 tests/smoke.py
PYTHONPATH=automation-bridge-python python3 tests/movement_smoke.py
```

The game starts in first person. **W/A/S/D** moves, **Shift** sprints, **Space**
jumps, **Ctrl** holds crouch, and **Z** holds prone. Click to capture the mouse
for looking; **Esc** releases it. Holding right mouse applies the ADS movement
speed reduction; weapon aiming is still future work.

Press **1**, **2** or **3** to inspect the street, shopfront or room, and **0** to
return to the player. Inspection disables movement input. **4** creates the
optional traversal course and puts the player at its stairs. Course lanes from
west to east contain a thin wall/corner, stairs, a high obstacle, 30°/60° ramps,
a low ceiling and narrow/wide doorways. The course is separate from the street.

Left mouse, R, F and Q/E still buffer fire, reload, inspect and lean intent for
future gameplay implementations. Tactical sprint, slide, mantle and lean are
not implemented yet.
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

The Lua movement tests cover jump timing, clearance, look, loading and equivalent
simulation at 30/60/144 presentation FPS. The native movement test builds an
optional course and drives input through actual Defold fixed ticks to check
speed, corners, thin-wall sweeps, stairs, slopes, ceilings, door widths and
entry into W2. Native validation currently targets macOS/Metal; browser/mobile
validation and advanced movement remain later milestones.

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
FX ignores player damage for hitmarkers. Other event producers arrive with their
respective gameplay systems; these declarations do not simulate firing or sound.

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
distance fog with the built-in 3D render pass. Local lights are metadata for the
later renderer; PBR, shadow maps, generated material textures and the full render
pipeline remain in step 6.

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
optional move_x, crouch, prone, aim, jump and look_x/look_y. Jump is a press on
the segment's first tick; look values are per-tick pixel deltas. Each drive is
limited to 2,400 ticks. `movement.result` returns completion and immutable final
metrics, so polling latency does not change the measured endpoint.
Discover them with `game.application_catalog(kind="command")`. For example:

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
