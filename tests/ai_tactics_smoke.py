"""Run the shared AI perception and tactics scenario in an owned native engine."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import socket
import subprocess
from automation_bridge import editor, engine


def main():
    root = Path(__file__).resolve().parents[1]
    output = root / "build/ai-tactics-native-validation"
    output.mkdir(parents=True, exist_ok=True)
    project = editor.open_project(root, start_if_needed=False)
    result = project.compile(timeout=120)
    assert result.success, result
    report = {"checks": [], "shots": [], "errors": []}
    report["sources"] = {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
                         for p in [*sorted((root / "game/ai").glob("*.lua")),
                                   root / "game/systems/ai.lua", root / "main/controller.script",
                                   root / "tests/ai_tactics_scenario.lua"]}
    with socket.socket() as reserved:
        reserved.bind(("127.0.0.1", 0)); profiler_port = reserved.getsockname()[1]
    log_path = output / "engine.log"
    with log_path.open("w") as log:
        process = subprocess.Popen([
            str(root / "build/arm64-osx/dmengine"), str(root / "build/default/game.projectc"),
            "--config=display.high_dpi=0", "--config=ai_tactics_validation.enabled=1",
            f"--config=profiler.remotery_port={profiler_port}",
        ], cwd=root, stdout=log, stderr=subprocess.STDOUT, env={**os.environ, "DM_SERVICE_PORT": "dynamic"})
        game = None
        seen = 0
        try:
            def port():
                assert process.poll() is None, log_path.read_text()
                match = re.search(r"Engine service started on port (\d+)", log_path.read_text())
                return int(match[1]) if match else None
            game = engine.connect(engine.wait_until(port, timeout=20), timeout=30)

            def completed():
                nonlocal seen
                lines = log_path.read_text().splitlines()
                for line in lines[seen:]:
                    if "ERROR:" in line:
                        report["errors"].append(line)
                    match = re.search(r"AI_TACTICS (START|CHECK|SHOT|PASS) (.*)", line)
                    if match:
                        kind, data = match[1], json.loads(match[2])
                        print(kind, json.dumps(data), flush=True)
                        if kind == "START":
                            report["engine"] = data
                        elif kind == "CHECK":
                            report["checks"].append(data)
                        elif kind == "SHOT":
                            shutil.copyfile(game.screenshot(resolution_multiplier=0.5).path, output / (data["id"] + ".png"))
                            report["shots"].append(data["id"])
                            game.command("ai_tactics.capture_ack", {"id": data["id"]})
                        else:
                            report["result"] = data
                seen = len(lines)
                assert not report["errors"], report["errors"]
                assert process.poll() is None, log_path.read_text()
                return report.get("result")
            engine.wait_until(completed, timeout=480)
            assert len(report["checks"]) == 13 and len(report["shots"]) == 5, report
        finally:
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
