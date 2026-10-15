"""Reproduce the spawn-to-forward-sprint navigation workload in the native profiler.
Run: PYTHONPATH=automation-bridge-python python3 tests/navigation_profile.py
Writes raw captures and summaries; leaves a normal encounter running at spawn.
"""
from dataclasses import asdict
import gzip
import json
from pathlib import Path
import time
from automation_bridge import editor, engine


def main():
    root = Path(__file__).resolve().parents[1]
    output = root / "build" / "forward-run-profile" / "optimized"
    output.mkdir(parents=True, exist_ok=True)
    project = editor.open_project(root, start_if_needed=False)
    game = project.build_and_run(timeout=180, focus=True)

    def cmd(name, data=None):
        return game.command(name, data or {})["result"]

    def state():
        return {"gameplay": cmd("gameplay.snapshot"), "ai": cmd("ai.snapshot"),
                "renderer": cmd("renderer.snapshot"), "audio": cmd("audio.snapshot")}

    def save(name, capture, extra):
        durations = sorted(frame.duration_ms for frame in capture.frames)
        frames = len(durations)
        elapsed = (capture.frames[-1].root.start_us-capture.frames[0].root.start_us)/1e6
        report = {"frames": frames, "fps": (frames-1)/elapsed,
                  "mean_frame_ms": sum(durations)/frames, "p95_frame_ms": durations[int(.95*(frames-1))],
                  "max_frame_ms": max(durations),
                  "ms_per_rendered_frame": {s.path: s.total.total_us/frames/1000 for s in capture.scopes()},
                  "scopes": [asdict(s) for s in capture.scopes()],
                  "counters": [asdict(c) for c in capture.counters()], **extra}
        (output / (name+".json")).write_text(json.dumps(report, indent=2)+"\n")
        with gzip.open(output / (name+"-raw.json.gz"), "wt") as stream:
            json.dump(asdict(capture), stream)
        print(name, "frames", len(durations), "mean frame ms", sum(durations)/len(durations), flush=True)
        for scope in capture.scopes():
            if scope.name in ("fixed.ai", "ai.navigation", "nav.endpoints"):
                print(scope.name, "ms/rendered frame", scope.total.total_us/len(durations)/1000, flush=True)

    recording = None
    try:
        engine.wait_until(lambda: game.state("world").value["ready"], timeout=60)
        engine.wait_until(lambda: cmd("renderer.snapshot")["ready"], timeout=60)
        cmd("gameplay.restart")
        cmd("ui.focus", {"focused": True});cmd("ui.pause", {"paused": False})
        cmd("ai.configure", {"damage_scale": 0})
        before = state()
        baseline = game.profiler.capture(frames=120, warmup_frames=30, thread="Main", timeout=20)
        save("spawn", baseline, {"before": before, "after": state()})
        recording = game.profiler.start_recording(thread="Main", max_frames=1600, read_timeout=.5)
        cmd("movement.drive", {"segments": [{"ticks": 720, "move_z": -1, "sprint": True}, {"ticks": 240}]})
        markers = []
        started = time.monotonic()
        while time.monotonic()-started < 30:
            sample = state()
            sample["recorded_frame"] = recording.frame_count
            sample["wall_seconds"] = time.monotonic()-started
            markers.append(sample)
            print("RUN", round(sample["wall_seconds"], 2), "z", round(sample["gameplay"]["z"], 2),
                  "pending", sample["ai"]["planning"], flush=True)
            if cmd("movement.result")["complete"]:
                break
            time.sleep(.7)
        capture = recording.stop();recording = None
        result = cmd("movement.result")
        save("forward", capture, {"markers": markers, "result": result})
        assert result["complete"], "Forward movement did not complete"
        assert all(not actor["recovery_failed"] for marker in markers for actor in marker["ai"]["actors"])
        errors = [line for line in project.console.read().lines if "ERROR:" in line]
        assert not errors, "\n".join(errors)
    finally:
        if recording:
            recording.stop()
        cmd("gameplay.restart")
        cmd("ui.focus", {"focused": True});cmd("ui.pause", {"paused": False})
        game.close()


if __name__ == "__main__":
    main()
