"""Compare cached and uncached sun shadows on the native GPU.

PYTHONPATH=automation-bridge-python python3 tests/shadow_cache_smoke.py
Requires Pillow and NumPy. Builds/owns its engine; all captures use the same
resolution and settings. Profiler samples are CPU frame scopes, not GPU timings.
"""
import argparse
import json
import shutil
from pathlib import Path

import numpy as np
from PIL import Image
from automation_bridge import editor, engine
from render_baseline import source_fingerprint

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--frames", type=int, default=1800)
    parser.add_argument("--skip-profile", action="store_true")
    args = parser.parse_args()
    output = ROOT / "build/shadow-cache-validation"
    output.mkdir(parents=True, exist_ok=True)
    project = editor.open_project(ROOT, start_if_needed=False)
    game = project.build_and_run(timeout=180, focus=True)
    report = {"source_sha256": source_fingerprint(), "stills": {}, "motion": {}, "profiles": []}

    def cmd(name, data=None):
        return game.command(name, data or {})["result"]

    def save(name):
        path = output / (name + ".png")
        shutil.copyfile(game.screenshot(after_frames=3).path, path)
        return path

    def compare(reference, optimized):
        a = np.asarray(Image.open(reference).convert("RGB"), dtype=np.int16)
        b = np.asarray(Image.open(optimized).convert("RGB"), dtype=np.int16)
        difference = np.abs(a - b)
        result = {"mean_channel_difference": float(difference.mean()),
                  "max_channel_difference": int(difference.max()),
                  "pixels_over_8_fraction": float((difference.max(axis=2) > 8).mean())}
        # Permit depth-encoding roundoff, but reject lost casters, contact
        # changes or visible seams. Temporal AA is disabled in motion checks.
        assert result["mean_channel_difference"] < .05, (reference, result)
        assert result["pixels_over_8_fraction"] < .001, (reference, result)
        return result

    try:
        engine.wait_until(lambda: cmd("world.snapshot")["ready"], timeout=90)
        engine.wait_until(lambda: cmd("renderer.snapshot")["ready"], timeout=90)
        report["renderer"] = cmd("renderer.snapshot")
        for name in ("street", "interior", "courtyard", "detail", "shadow_distance",
                     "shadow_cutout", "shadow_remote", "sunset", "night"):
            cmd("capture.shot", {"name": name})
            paths = []
            for enabled in (False, True):
                cmd("renderer.configure", {"shadow_cache": enabled})
                game.wait_frames(40)
                paths.append(save(name + ("-cached" if enabled else "-reference")))
            report["stills"][name] = compare(*paths)
            print("PASS cache still", name, report["stills"][name], flush=True)

        for name in ("street", "shadow_cutout", "shadow_remote"):
            paths = {}
            for enabled in (False, True):
                cmd("capture.shot", {"name": name, "temporal_live": True})
                cmd("renderer.configure", {"shadow_cache": enabled, "temporal_aa": False})
                for frame in (0, 1, 15, 30, 60, 90, 120):
                    cmd("capture.frame", {"frame": frame})
                    game.wait_frames(3)
                    path = save(f"{name}-motion-{frame}-{'cached' if enabled else 'reference'}")
                    if enabled:
                        report["motion"][f"{name}/{frame}"] = compare(paths[frame], path)
                    else:
                        paths[frame] = path
            print("PASS cache motion without TAA", name, flush=True)

        if not args.skip_profile:
            for name in ("street", "shadow_distance"):
                cmd("capture.shot", {"name": name, "temporal_live": True})
                cmd("capture.play", {"playing": True})
                for enabled in (False, True, False, True):
                    cmd("renderer.configure", {"shadow_cache": enabled})
                    game.wait_frames(40)
                    capture = game.profiler.capture(frames=args.frames, timeout=45)
                    step = next(s for s in capture.scopes() if s.path == "Step" and s.thread_name == "Main")
                    draws = next(c for c in capture.counters() if c.name == "DrawCalls")
                    result = {"shot": name, "cache": enabled, "fps": 1000000 / step.total.avg_us,
                              "delivered_samples": step.frames_seen, "mean_ms": step.total.avg_us / 1000,
                              "p95_ms": step.total.p95_us / 1000, "draw_calls": draws.values.avg}
                    report["profiles"].append(result)
                    print("PROFILE", json.dumps(result), flush=True)
        report["scope"] = "Fixed resolution; moving camera with live TAA and frozen gameplay. CPU frame scopes, not GPU or sustained combat timings."
        report["complete"] = True
    finally:
        (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
        game.close_engine()
        game.close()
    errors = [line for line in project.console.read().lines if "ERROR:" in line]
    assert not errors, "\n".join(errors)
    print("PASS cached sun-shadow quality and clean shutdown", flush=True)


if __name__ == "__main__":
    main()
