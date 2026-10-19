"""Run the shared first-person viewmodel scenario in an owned native engine."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
from automation_bridge import editor, engine


def main():
    root = Path(__file__).resolve().parents[1]
    output = root / "build/viewmodel-native-validation"
    output.mkdir(parents=True, exist_ok=True)
    project = editor.open_project(root, start_if_needed=False)
    result = project.compile(timeout=120)
    assert result.success, result
    report = {"checks": [], "shots": [], "errors": []}
    report["sources"] = {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
                         for p in [*sorted((root / "game/player").glob("*.lua")),
                                   root / "game/systems/player.lua", root / "game/systems/weapons.lua", root / "game/combat.lua",
                                   *sorted((root / "game/weapons").glob("*.lua")), *sorted((root / "weapons").glob("*")), root / "main/controller.script",
                                   root / "game/presentation.lua", root / "tests/viewmodel_scenario.lua"]}
    log_path = output / "engine.log"
    with log_path.open("w") as log:
        process = subprocess.Popen([
            str(root / "build/arm64-osx/dmengine"), str(root / "build/default/game.projectc"),
            "--config=display.high_dpi=0", "--config=viewmodel_validation.enabled=1",
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
                    match = re.search(r"VIEWMODEL (CHECK|SHOT|PASS) (.*)", line)
                    if match:
                        kind, data = match[1], json.loads(match[2])
                        print(kind, json.dumps(data), flush=True)
                        if kind == "CHECK":
                            report["checks"].append(data)
                        elif kind == "SHOT":
                            shutil.copyfile(game.screenshot(resolution_multiplier=0.5).path, output / (data["id"] + ".png"))
                            report["shots"].append(data["id"])
                        else:
                            report["result"] = data
                seen = len(lines)
                assert not report["errors"], report["errors"]
                assert process.poll() is None, log_path.read_text()
                return report.get("result")
            engine.wait_until(completed, timeout=300)
            assert len(report["checks"]) == 19 and len(report["shots"]) == 19, report
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
