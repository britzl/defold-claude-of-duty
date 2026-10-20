"""Run the shared animated atmosphere scenario in an owned native engine."""
from dataclasses import asdict
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import socket
import sys
import threading
import subprocess
from automation_bridge import editor, engine


def main():
    root = Path(__file__).resolve().parents[1]
    output = root / "build/animated_atmosphere-native-validation"
    output.mkdir(parents=True, exist_ok=True)
    project = editor.open_project(root, start_if_needed=False)
    result = project.compile(timeout=120)
    assert result.success, result
    profile_only = "--profile-only" in sys.argv
    report = json.loads((output / "report.json").read_text()) if profile_only else {"checks": [], "shots": [], "errors": []}
    paths=[*sorted((root/"game/render").glob("*.lua")),*sorted((root/"render").glob("*.glsl")),*sorted((root/"render").glob("*.fp")),root/"render/game.render_script",root/"tests/animated_atmosphere_scenario.lua"]
    report["sources"]={str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
    with socket.socket() as reserved:
        reserved.bind(("127.0.0.1", 0)); profiler_port = reserved.getsockname()[1]
    log_path = output / ("profile-engine.log" if profile_only else "engine.log")
    with log_path.open("w") as log:
        process = subprocess.Popen([
            str(root / "build/arm64-osx/dmengine"), str(root / "build/default/game.projectc"),
            "--config=display.high_dpi=0", f"--config=animated_atmosphere_validation.enabled={0 if profile_only else 1}",
            f"--config=profiler.remotery_port={profiler_port}",
        ], cwd=root, stdout=log, stderr=subprocess.STDOUT, env={**os.environ, "DM_SERVICE_PORT": "dynamic"})
        game = None
        seen = 0
        stop_guard = threading.Event()
        guard = None
        try:
            def port():
                assert process.poll() is None, log_path.read_text()
                match = re.search(r"Engine service started on port (\d+)", log_path.read_text())
                return int(match[1]) if match else None
            game = engine.connect(engine.wait_until(port, timeout=20), timeout=30, profiler_url=f"ws://127.0.0.1:{profiler_port}/rmt")

            def completed():
                nonlocal seen
                lines = log_path.read_text().splitlines()
                for line in lines[seen:]:
                    if "ERROR:" in line:
                        report["errors"].append(line)
                    match = re.search(r"ATMOSPHERE (START|CHECK|SHOT|PASS) (.*)", line)
                    if match:
                        kind, data = match[1], json.loads(match[2])
                        print(kind, data.get("id", data.get("name", "complete")), flush=True)
                        if kind == "START":
                            report["engine"] = data
                        elif kind == "CHECK":
                            report["checks"].append(data)
                        elif kind == "SHOT":
                            shutil.copyfile(game.screenshot(resolution_multiplier=0.5).path, output / (data["id"] + ".png"))
                            report["shots"].append(data["id"])
                            report.setdefault("shot_states", {})[data["id"]] = data["renderer"]
                            game.command("atmosphere.capture_ack", {"id": data["id"]})
                        else:
                            report["result"] = data
                seen = len(lines)
                assert not report["errors"], report["errors"]
                assert process.poll() is None, log_path.read_text()
                return report.get("result")
            if profile_only:
                engine.wait_until(lambda: game.command("world.snapshot", {})["result"]["ready"] and game.command("renderer.snapshot", {})["result"]["ready"], timeout=90)
            else:
                engine.wait_until(completed, timeout=480)
            assert len(report["checks"]) == 8 and len(report["shots"]) == 18, report
            # Short diagnostic windows; record scope/sample counts, never claim
            # sustained combat FPS or GPU time from CPU submission measurements.
            game.command("ai.configure", {"enabled": False})
            game.command("ui.focus", {"focused": True})
            game.command("ui.pause", {"paused": False})
            game.command("world.view", {"name": "street"})
            report["costs"] = {}
            # OS focus events can arrive after the initial automation resume.
            # Keep this diagnostic engine active; the acceptance fixture above
            # separately verifies genuine pause/focus behavior.
            focus_restores = []
            def keep_active():
                while not stop_guard.wait(.2):
                    try:
                        state = game.command("ui.snapshot", {})["result"]
                        if not state["focused"]:
                            game.command("ui.focus", {"focused": True}); focus_restores.append("focus")
                        if state["paused"]:
                            game.command("ui.pause", {"paused": False}); focus_restores.append("pause")
                    except Exception as error:
                        focus_restores.append(str(error)); return
            guard = threading.Thread(target=keep_active, daemon=True); guard.start()
            for label, rate, speed in [("fixed", 0, 0), ("animated", .05, 1)]:
                game.command("renderer.configure", {"hour": 16.5, "weather_time": 1745,
                    "time_rate": rate, "weather_speed": speed})
                game.wait_frames(80)
                before = game.command("renderer.snapshot", {})["result"]
                restores = len(focus_restores)
                sample = game.profiler.capture(frames=240, warmup_frames=30, timeout=30)
                report["costs"][label] = {"renderer": game.command("renderer.snapshot", {})["result"],
                    "scopes": [asdict(v) for v in sample.scopes()],
                    "counters": [asdict(v) for v in sample.counters()],
                    "focus_restores_during_sample": focus_restores[restores:]}
                after = report["costs"][label]["renderer"]
                if rate:
                    assert after["requested_hour"] > before["requested_hour"] and after["environment_updates"] > before["environment_updates"], "Profile animation was paused"
                print("PROFILE", label, flush=True)

        finally:
            stop_guard.set()
            if guard: guard.join(timeout=3)
            if game:
                game.close_engine()
                game.close()
            if process.poll() is None:
                process.terminate()
            process.wait(timeout=15)
            (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    assert "ERROR:" not in log_path.read_text(), log_path.read_text()


if __name__ == "__main__":
    main()
