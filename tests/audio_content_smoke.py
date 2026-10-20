"""Run the shared audio content scenario in an owned native engine."""
import hashlib
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import zipfile
from automation_bridge import editor, engine


def main():
    root = Path(__file__).resolve().parents[1]
    output = root / "build/audio-content-native-validation"
    output.mkdir(parents=True, exist_ok=True)
    project = editor.open_project(root, start_if_needed=False)
    result = project.compile(timeout=120)
    assert result.success, result
    # Editor compile refreshes its engine archive, not Bob's older build binary.
    with zipfile.ZipFile(root / ".internal/cache/engine-archives/arm64-osx/build.zip") as archive:
        executable=output / "dmengine"
        executable.write_bytes(archive.read("dmengine"));executable.chmod(0o755)
    report = {"checks": [], "errors": []}
    paths=[*sorted((root/"game/audio").glob("*.lua")),root/"game/systems/audio.lua",
           root/"game/physics/defold.lua",root/"game/ui/controller.lua",root/"game/weapons/ballistics.lua",
           root/"physics/body.collisionobject",root/"physics/grenade.collisionobject",root/"game.project",
           root/"audiosynth/src/audiosynth.cpp",root/"main/controller.script",root/"tests/audio_content_scenario.lua"]
    report["sources"]={str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
    report["engine_sha256"]=hashlib.sha256(executable.read_bytes()).hexdigest()
    with socket.socket() as reserved:
        reserved.bind(("127.0.0.1", 0)); profiler_port = reserved.getsockname()[1]
    log_path = output / "engine.log"
    with log_path.open("w") as log:
        process = subprocess.Popen([
            str(executable), str(root / "build/default/game.projectc"),
            "--config=display.high_dpi=0", "--config=audio_synthesis.verify=1", "--config=audio_content_validation.enabled=1",
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
                    match = re.search(r"AUDIO_CONTENT (START|CHECK|PASS) (.*)", line)
                    if match:
                        kind, data = match[1], json.loads(match[2])
                        print(kind, json.dumps(data), flush=True)
                        if kind == "START":
                            report["engine"] = data
                        elif kind == "CHECK":
                            report["checks"].append(data)
                        else:
                            report["result"] = data
                seen = len(lines)
                assert not report["errors"], report["errors"]
                assert process.poll() is None, log_path.read_text()
                return report.get("result")
            engine.wait_until(completed, timeout=480)
            assert len(report["checks"]) == 16, report
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
