# AudioSynth native extension

The default audio backend generates the procedural bank in C++: waveform math,
Park–Miller random streams, filters, room echoes, endpoint fades, peak/RMS
statistics and little-endian PCM16 WAV packing. Lua keeps the catalog and tuning
parameters in `game/audio/synth.lua`, scheduling and playback in
`game/systems/audio.lua`, and Defold resource ownership in `game/audio/defold.lua`.
The original Lua generator remains the reference implementation.

Defold automatically discovers this extension and builds it for macOS and
HTML5/Wasm. Rebuild the custom engine after C++ changes; hot reload cannot update
native code. Arithmetic uses doubles with fast math and fused multiply-add
disabled. A fixed ring buffer retains the two room-echo delays; a `dmArray`
owns the WAV. No per-sample data crosses the Lua/native boundary.

## Configuration

- `audio_synthesis.backend=native` is the engine default. Set it to `lua` for
  fallback and matched performance comparisons. Standalone Lua tests use Lua.
- `audio_synthesis.verify=1` runs engine-only parity/ownership fixtures at startup
  and compares all 76 generated native WAVs with Lua before resource creation.
  WAV bytes, frame counts and durations must match exactly; peak/RMS tolerance
  is 1e-12. Verification must be off when profiling performance.
- `audio_synthesis.fingerprints=1` adds WAV byte hashes and metadata to
  `audio.snapshot` for comparisons. This optional diagnostic hashes each WAV
  during loading, so use the same flag in both compared runs.

Both backends process chunks of at most 1,024 samples under the existing soft
2 ms loading deadline. The native safety cap is 131,072 samples per update;
Lua retains its original 8,192 cap. Native generation can therefore use its time
budget without the old minimum of 107 updates. Individual chunks, final Lua
string copying and Defold resource creation do not yield. `audio.snapshot`
reports the chosen backend, verified sound count, full accumulated CPU work and
peak update cost. `world.snapshot.timings.audio_ready` records bank completion;
`renderer_ready` and `playable` distinguish the concurrent renderer work.

## Bindings and lifetime

| Call | Result |
| --- | --- |
| `audiosynth.new(recipe, seed, parameters, stream)` | Owned job userdata. `parameters` comes from `synth.parameters(recipe)`; `stream` uses the existing `kind/name/variant` seed tag. |
| `audiosynth.step(job, sample_count)` | No values while pending; completed binary WAV string and `{frames,duration,peak,rms}` when finished. Accepts 1–65,536 samples per call. |
| `audiosynth.close(job)` | Releases native storage; idempotent and also used by `__gc`. |
| `audiosynth.fingerprint(wav)` | Full-length binary-data hash for optional validation, including bytes after embedded zeros. |

Jobs reject stepping after completion or close. The returned Lua string owns its
bytes and survives native job closure. `game/audio/generator.lua` closes completed
jobs immediately; subsystem teardown closes partially generated jobs. Input
checks precede allocation, and userdata owns allocations across Lua errors.
Durations are bounded to one sample through 30 seconds; variants are 1–3.

## Validation

After building the custom engine and compiling resources:

```sh
lua tests/audio_test.lua
lua tests/runtime_test.lua
PYTHONPATH=automation-bridge-python python3 tests/loading_profile.py --verify-audio --audio-fingerprints --output captures/audio-verify
PYTHONPATH=automation-bridge-python python3 tests/loading_profile.py --audio-backend lua --audio-fingerprints --output captures/audio-lua
PYTHONPATH=automation-bridge-python python3 tests/loading_profile.py --audio-backend native --audio-fingerprints --output captures/audio-native
PYTHONPATH=automation-bridge-python python3 tests/audio_smoke.py
```

Bundle a debug HTML5 build with `tests/audio_browser.project`, then run:

```sh
PLAYWRIGHT_MODULE=/path/to/playwright node tools/validate_audio_browser.mjs --bundle=/path/to/bundle --output=captures/audio-browser
```

The browser harness accepts `--browser=/path/to/chromium` and performs verification
followed by three alternating fresh Lua/native pairs. Both performance harnesses
use native world meshes. Compare PCM bytes and timings within each platform;
cross-platform math-library equality is not assumed. Full startup also depends on
renderer baking, so audio CPU savings do not directly equal readiness savings.
