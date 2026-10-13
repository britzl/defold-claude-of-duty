# Defold Claude of Duty

Runtime-generated port targeting Defold 1.14.0. See [PLAN.md](PLAN.md).

The first plan step is implemented: a gameplay controller, six subsystem modules,
120 Hz fixed simulation, metre-based 3D physics with gravity -20.6 m/s², buffered
input, gameplay notifications, centralized damage, and separate camera/HUD
presentation. The scene currently shows a crosshair and health. World generation,
capsule movement, weapons, soldiers and synthesized audio are subsequent work;
the system modules establish their state ownership and integration points.

## Run and validate

Open `game.project` in Defold 1.14.0, fetch libraries, then build and run.
The existing Automation Bridge dependency supports native smoke checks.
Run the engine-independent regression suite from the repository root:

```sh
lua tests/runtime_test.lua
```

With the project open in Defold, the native smoke test builds the game, checks
timing, input, damage and HUD updates, then closes the engine it launched:

```sh
PYTHONPATH=automation-bridge-python python3 tests/smoke.py
```

Input bindings normalize W/A/S/D, mouse movement, left/right mouse, Space,
Shift, Ctrl, Z, R, F and Q/E into movement, look, fire/aim, jump, sprint, crouch,
prone, reload, inspect and lean intent. These are buffered commands for the
future gameplay implementations; movement and firing are not yet implemented.
Gamepad/touch adapters can feed the same `game.input` API later.

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

Actor and camera game objects are wired now. Future world batches and collision
objects belong to the world module; future enemy game objects belong to AI.
Each system must release its generated Defold resources in `final`.

## Automation

The debug bridge exposes `gameplay.snapshot` (timing, input intent, health and
physics settings) and `gameplay.damage` (queue a hit through the combat owner).
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
