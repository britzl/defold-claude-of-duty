# WorldMesh native extension

This in-repository Defold extension implements world mesh construction/batching
(loading step 5) and Defold buffer creation/filling (step 6). Defold discovers
`ext.manifest` automatically and compiles the C++ sources with the custom engine,
including for HTML5/Wasm. Build once in the editor after changing the extension;
hot reload alone cannot update C++ code. Tested with Defold 1.14.0.

Shape recipes, visible-face clipping, collision/navigation metadata, and the
decoration random stream remain in Lua. `game/world/generator.lua` passes each
shape, material, shade and clipped rectangles to C++. The extension generates
the same triangles and spatial batches, then writes float32 streams using
`dmBuffer`. The existing Lua adapter still creates mesh game objects, creates
buffer resources and binds those resources to the components.

Intermediate geometry arithmetic uses doubles, with float conversion only at
the same boundary as the original Lua-to-buffer assignment. Fast math and fused
multiply-add are disabled. Vertex order, batch order, bounds, tessellation,
material attributes and shared-edge subdivision are preserved. Glass retains
its small Lua geometry generator and uses the native buffer packer.

Variable-length geometry uses Defold's `dmArray`; shared-edge and batch lookup
use `dmHashTable64`. Coordinates, rectangles and bounds are inline double
values. Because Defold containers use memcpy semantics, batches and edge lines
are stored as owned pointers and explicitly destroyed by the builder. No STL
array, vector or map containers are used.

## Configuration

The game defaults to `world_mesh.backend=native`. For comparisons, launch the
same engine with `--config=world_mesh.backend=lua`. Standalone Lua tests use the
Lua implementation without requiring an engine.

`--config=world_mesh.verify=1` runs primitive/ownership tests at initialization
and compares every generated native shape against the Lua reference during
loading. It compares float32 bits (including signed zero) and double bounds;
any mismatch is an error. Verification deliberately does extra work and must
be disabled for timing runs.

## Lua bindings

These bindings serve the world generator; the original Lua mesh module remains
the reference implementation.

| Call | Result |
| --- | --- |
| `worldmesh.begin(edges, chunk_size, max_vertices)` | Builder userdata containing a copied/sorted shared-edge registry. |
| `worldmesh.append(builder, shape, material, shade, visible_faces)` | Generated vertex count; geometry is appended to native batches. |
| `worldmesh.finish(builder)` | Ordered Lua batch metadata: keys, material, chunk, vertex count, shape count, bounds and native handles. |
| `worldmesh.take_buffer(builder, index)` | A Lua-owned Defold buffer containing the batch's six streams and AABB metadata. Can be called once per batch. |
| `worldmesh.pack(batch)` | A Lua-owned buffer for a small existing Lua batch, including glass's double-precision translation into local coordinates. |
| `worldmesh.close(builder)` | Releases untaken geometry. Idempotent; also called by userdata garbage collection. Returned buffers remain valid. |
| `worldmesh.verify(builder, shape, material, shade, visible_faces, reference)` | Checks native output against a Lua mesh and raises on mismatch. |
| `worldmesh.clock()` | Monotonic seconds for complete loading-stage timestamps. |

The builder rejects appends after finish and access after close. Lua retains
the builder until all batches are installed, closes it after upload, and also
closes it when loading is cancelled. Each native upload handles one bounded
batch (at most 12,288 vertices); the existing 4 ms loading deadline is checked
between batches. Individual native calls do not yield.

## Validation and measurements

After an editor build, run separate fresh processes for each backend:

```sh
PYTHONPATH=automation-bridge-python python3 tests/loading_profile.py --backend native --verify --output captures/native-check
PYTHONPATH=automation-bridge-python python3 tests/loading_profile.py --backend lua --output captures/loading-lua
PYTHONPATH=automation-bridge-python python3 tests/loading_profile.py --backend native --output captures/loading-native
```

The macOS harness saves source hashes, installed stream fingerprints, complete
application timestamps, Remotery samples and profiler coverage. The `playable`
timestamp means both world/audio loading and renderer preparation are ready;
`gameplay` separately records the first unpaused simulation tick after loading.
Application timestamps start at world initialization, excluding engine startup.

Bundle HTML5 with `tests/market_browser.project` as an additional settings file,
then run the actual Wasm engine in Chromium:

```sh
PLAYWRIGHT_MODULE=/path/to/playwright node tools/validate_native_mesh_browser.mjs --bundle=/path/to/bundle --output=captures/native-browser
PLAYWRIGHT_MODULE=/path/to/playwright node tools/validate_market_browser.mjs --bundle=/path/to/bundle --output=captures/native-browser-market
```

Both browser tools accept `--browser=/path/to/chromium`. The mesh harness runs
verification once and then three alternating Lua/native pairs. It checks all
installed stream hashes and bounds after the measured readiness point, with
identical settings and assets for each pair. The market harness checks real
Bullet navigation and actor routes. `tests/full_market_smoke.py --quick` runs
the corresponding physics/route matrix and inspection captures on macOS.

Compare Lua/native results **within each platform**: the Lua runtimes and math
libraries can differ between native macOS and Wasm. Keep verification disabled
for performance comparisons. Full readiness also depends on audio synthesis
and renderer baking, so its improvement is smaller than the mesh stages alone.
