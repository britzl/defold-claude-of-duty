# Parity baseline v1

[contract.json](contract.json) is the acceptance matrix: 24 feature scenarios with
reference source paths, expected behavior, a verification procedure, existing
coverage, and eleven recorded adaptation decisions. `implemented-core` describes
existing code; it does not mean the scenario has passed parity review.
[reference-lock.json](reference-lock.json) pins the runtime source snapshots and
all 71 production camera requests, including FOV, lighting and fixture intent.

The current acceptance targets, selected on 2026-10-15, are **Mac native and
desktop browser at 60 FPS**. Mobile qualification is outside this gate. Proposed
1280 × 720 high-quality budgets are:

| Metric | Mac Metal | Mac desktop browser |
| --- | --- | --- |
| Presented frame p95 / p99 / worst | 18.3 / 25 / 50 ms | 18.3 / 25 / 50 ms |
| CPU p95 / GPU p95 | 12 / 14 ms | 12 / 14 ms |
| Cold local load | 10 s | 15 s |
| Peak measured resident memory | 1,024 MiB | 1,536 MiB |

These thresholds are engineering proposals, not measured results. The contract
requires three release runs, each with 60 seconds of warmup and 300 seconds of
full-map combat sampling. Report actual framebuffer/internal resolution,
backend, device/OS/browser, dropped samples, CPU/GPU timing and memory scope.
The complete stress scenario remains unqualified while grenades, ragdolls and
other combat effects are missing. Frozen capture frames and an FPS overlay do not satisfy
this protocol.

## Weapon animation increment — 2026-10-19

Step 7 adds generated weapon detail, shared 17-joint arms with body-fixed shoulder
IK, articulated grips, reload/charge hand tracks and fixed-tick lag/sway/stride
motion. Full ADS and the collimated dot remain on the camera axis. The shared
native/release-WebGL fixture passes 19 checks with 19 captures per backend;
ammunition timing and interrupted empty reloads retain their production owner.
The 268-check Lua matrix includes frame-rate equivalence and singular IK cases.
Seven Three.js hip/ADS/indoor still requests are available for review. Reduced
mesh detail, bounded sleeve length correction, different lighting/materials and
unqualified reference/Kaigen motion remain documented adaptations and gates.
The refreshed source lock carries no stale capture receipts. These checks do
not establish exact visual parity or sustained performance.

## Player health increment — 2026-10-19

Step 6 implements delayed/ramped regeneration, fall damage, projectile/hit/blast
suppression and low-health/recovery presentation. The shared 13-case fixture
passes on Mac Metal and desktop Chrome WebGL2/ANGLE Metal; three pixel gates per
backend verify colour loss and restoration. The reference timing is retained;
projectile ownership/visibility and the existing pre-AgX composite are documented
adaptations. Explosion damage and heartbeat audio remain their later steps.
The source lock is refreshed without stale capture receipts. These gameplay and
visual smoke checks do not claim controlled reference or sustained-performance
parity. Commands and evidence directories are in the repository README.

## Traversal and camera increment — 2026-10-17

Step 5 implements thin-obstacle vaulting, the reference camera motion families,
sprint/ADS FOV and additive impulse channels. The shared native/WebGL fixture
uses real Bullet geometry and production fixed ticks; standalone tests compare
camera state and sampled poses at 30, 60 and 144 presentation FPS. See the
repository README for commands, adaptation details and qualification scope.

The refreshed source lock carries the current runtime and contract, with no
stale visual receipts. The previous architecture comparison remains in
`world-detail-baseline-v1.json`. Traversal fixture receipts are implementation
evidence, not controlled reference motion captures or a sustained 60 FPS pass.

## Architecture and dressing increment — 2026-10-15

Step 4 implements source-derived setbacks, balconies, windows, the gate, ruined
floors, room programmes and all authored dressing families. The map adaptation
record describes the retained W2/E2 layouts, route-safe placement shifts and
simplified collision/tessellation. Seven room nodes extend the graph to 196
nodes and 201 links, with 108 six-actor route queries on native and WebGL.

The native full walk/patrol matrix passed; later stall collision refinements
passed fresh bidirectional capsule checks on both backends. Four native stills
have exact repeats; three matching Three.js camera views document the street,
interior and courtyard. Captures retain the visible lighting/exposure and
geometry differences. They are implementation evidence, not final visual or
sustained 60 FPS qualification. `tests/world_detail_capture.py` records resource
counts and frozen-scene render/CPU counters alongside its images. The historical
[world-detail-baseline-v1.json](world-detail-baseline-v1.json) retains four native
and three Three.js capture receipts;
omitted cameras are not marked as captured. See the README for final measured
costs and validation commands.

## Complete material catalogue increment — 2026-10-15

The current lock includes nineteen surface families, the full market and capture
catalogue v13 (71 cameras). The fifteen additions cover sand, corrugated metal,
burlap and foliage at close range, distance and grazing angles, plus leaf-card
back faces and sun/local shadows. Native tier checks and a focused 62-stage
medium-tier WebGL fixture are documented in the repository README. Their images
are implementation evidence, not matched cross-engine receipts. Six new foliage
reference shots are explicitly pending; the earlier six pending reference
fixtures remain open. The lock carries no stale captures from older catalogues.

## Full-map source increment — 2026-10-15 (historical)

That increment pinned the expanded 104 m market and refreshed contract.
[excerpt-baseline-v1.json](excerpt-baseline-v1.json) preserves the previous source
identity and three capture receipts. Those native images describe the old map;
they do not qualify this source increment. The current lock deliberately carries
no old capture evidence. That catalogue contained 56 production camera
requests; eight additional layout inspection views are smoke-test artifacts,
not a new matched visual baseline.

Full-map layout validation passed native player/AI traversal, 78 route queries on
each backend, all 194 bidirectional Bullet links, and eight browser minimap pixel
checks. Commands and measured resource counts are documented in the repository README. Source/layout implementation is separate from exact
architectural fidelity and the sustained 60 FPS acceptance gate.

## Historical excerpt validation — 2026-10-15

- Five Node adapter/export tests, seven Python provenance tests and the three
  existing Lua capture tests passed. CLI checks passed for an unchanged lock and
  rejected an intentionally altered contract hash.
- `captures/parity/threejs-baseline-final` verified 46 shot pairs before a late
  page load timed out. That failed manifest is retained and explicitly imported
  as partial evidence, including its failure record.
- `captures/parity/threejs-recovery` verified the remaining four shot pairs using
  eight independent browser launches (`--browser-batch=1`). All 50 supported
  catalogue shots therefore have exact repeated pixels; six remain pending.
  The browser lifetime is now bounded by the adapter. A successful uninterrupted
  full-catalogue run with that change has not been claimed.
- The existing 56-shot native manifest at
  `captures/rendering/photographic-final/launch-1` was checked against the then-current
  runtime source and image hashes. It is prior capture evidence; native gameplay
  and the full native capture suite were not rerun for this tooling increment.

## Reproduce and review

Run from the Defold repository. The source archives are external inputs; pass
their paths explicitly. Both currently lack Git metadata, so their exact commit
IDs are unavailable. Content hashes identify the actual inputs. The hosted
Kaigen build ID is recorded separately and is not treated as their commit ID.

```sh
# Export the live production catalogue without launching Defold.
mkdir -p captures/parity
lua tools/export_parity.lua catalog > captures/parity/catalog.json

# Requires Lua, Node, and the reference checkout's installed Playwright/Chromium,
# pngjs and Vite dependencies. Output must be a new directory.
node tools/capture_reference.mjs \
  --source=/path/to/Claude-of-Duty-main \
  --baseline=captures/parity/catalog.json \
  --repeats=2 --output=captures/parity/threejs-run

# Native capture: requires the open Defold editor, Automation Bridge and Pillow.
PYTHONPATH=automation-bridge-python python3 tests/render_baseline.py \
  --launches=2 --output=captures/parity/defold-run

# Verify the contract, source snapshots and catalogue against the checked-in lock.
# Optional --capture also checks manifest provenance, state and image checksums.
python3 tools/parity_baseline.py \
  --threejs=/path/to/Claude-of-Duty-main \
  --kaigen=/path/to/kaigen-claude-of-duty-main --check \
  --capture=captures/parity/threejs-run/manifest.json \
  --capture=captures/parity/defold-run/launch-1/manifest.json

# Create labelled visual comparisons, with missing/pending panels left visible.
python3 tools/compare_render_baselines.py \
  captures/parity/defold-run/launch-1/manifest.json \
  captures/parity/threejs-run/manifest.json --output=captures/parity/comparison

node --test tests/reference_contract_test.mjs
python3 tests/parity_baseline_test.py
```

Use `--shots=smg_ads,sky_night,moon,laboratory,material_wood,weapon_fire` for a focused
adapter check. Omitted shots are not evidence. `--repeats` defaults to one; two
or more pages are needed for the adapter's exact-pixel repeat check. The browser
restarts after eight pages by default to bound its lifetime during long catalogues.
`--browser-batch=1` uses a fresh browser for every image and also tests repeatability
across browser launches. This is independent of the shot repeat count.
The manifest's `complete` applies to the requested selection, not the full catalogue
or cross-engine parity. The source lock separately lists captured, repeated,
pending and not-run shots. Failed captures throw and retain an error receipt.

If a long run fails, retry its failed/not-run shots into a new output directory.
Ordinary `--capture` rejects failed manifests. `--partial-capture=path/to/manifest.json`
explicitly retains only its validated successful images alongside the original
error and failed-shot list; it never converts the run into a pass. Include the
successful retry separately with `--capture`. This avoids discarding verified
earlier images or hiding the failure.

After intentional runtime, catalogue or contract changes, review the diff and
run the lock command with `--update` instead of `--check`, supplying all capture
manifests to retain as evidence. Updating without `--capture` deliberately stores
no evidence; old captures must not silently qualify a new baseline. Source hashes
cover runtime resources (including Defold audio/input and Kaigen shaders/assets),
while the adapter records its own code/fixture hash. The legacy capture hashes
use a narrower documented algorithm and are verified separately.

Capture images stay under ignored `captures/`. The tracked lock keeps manifest
checksums, actual camera/light/exposure state and compact receipts; it does not make those local images available on
another machine. `--check` without `--capture` validates only the source lock and
contract, so it works without archived images. Keep an external copy of the
complete run directories when distributing evidence.

## What the comparisons mean

Defold uses seed 1337 and an identity level transform; both references use
`0x5eed1234`, yaw 0.5877 and translation `(0.9, 0, 1.34)`. The adapter transforms
the same level-space camera position/target and uses matching vertical FOV and
0.1–500 m world clip planes. Different RNGs, map content and light orientations
are recorded differences, not normalized away. Daylight/sunset/night are fixed
at 16.5/19.2/1.5 solar hours. Actual light direction, framebuffer, renderer,
settings, weapon and GPU metered exposure are recorded for every reference shot.

The Three.js adapter imports the production Defold laboratory triangles and uses
the reference material recipes, with aliases for matching surface families.
Uniform sphere roughness/metalness remains controlled. Tint, weathering masks,
indoor attenuation and exposure models differ; these images are for visual
review, not proof of matched radiance or reference feature parity. Actual
geometry support is reported per image.

Six catalogue shots remain explicitly pending in the Three.js adapter:

- `shadow_cutout`, `local_lights`, `glass`: fixture shading/light registration
  needs an equivalent reference implementation and qualification.
- `weapon_fire`, `combat_effects`, `combat_glass`: transient event timelines
  need a frame-addressed reference implementation.

Reference motion sweeps, audio/gameplay scenario execution and final matched
full-map lighting are still qualification work. Exact pixels are required only
for repeats on the same controlled backend; cross-engine similarity has no
automatic pixel score.

## Kaigen availability

The [published demo](https://kaigen3d.com/demos/claude-of-duty/) loaded and rendered
gameplay on 2026-10-15. Its HTML identifies build `cd0e50316eb8` and asset directory
`a24065352205d`. This is an available observational reference. Its relationship
to the local source archive is unverified, and no controlled camera, fixed-frame
capture or matching laboratory adapter has been verified.

The local archive lacks the `hz` engine dependency and CLI. Controlled Kaigen
captures, actual exposure/quality metadata and sustained performance are
**unavailable**. To close that gate, obtain the matching runnable engine/build,
add frame-addressed camera/scene control, port the laboratory, capture repeats,
and pin the resulting metadata and evidence. The hosted demo alone does not
close it or block independent map/gameplay implementation.
