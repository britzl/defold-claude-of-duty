"""Native real-projectile suppression, cover duck and recovery scenario."""
import json
from pathlib import Path
import shutil
from automation_bridge import editor, engine


def main():
    root = Path(__file__).resolve().parents[1]
    output = root / "build" / "suppression-validation"
    output.mkdir(parents=True, exist_ok=True)
    project = editor.open_project(root, start_if_needed=False)
    game = project.build_and_run(timeout=180)

    def cmd(name, data=None):
        return game.command(name, data or {})["result"]

    captured = set()
    try:
        engine.wait_until(lambda: game.state("world").value["ready"], timeout=25)
        cmd("ai.validate_suppression")

        def done():
            if cmd("ui.snapshot")["paused"]:
                cmd("ui.focus", {"focused": True})
                cmd("ui.pause", {"paused": False})
            result = cmd("ai.suppression_result")
            for phase in result["report"]:
                if phase not in captured:
                    captured.add(phase)
                    print(phase, result["report"][phase], flush=True)
                    shot = game.screenshot(resolution_multiplier=1)
                    shutil.copyfile(shot.path, output / (phase.lower()+".png"))
            if result["phase"] == "done":
                (output / "native.json").write_text(json.dumps(result, indent=2)+"\n")
                return True
            return False

        engine.wait_until(done, timeout=45, interval=.1)
        cmd("gameplay.restart")
        game.wait_frames(4)
        s = cmd("ai.snapshot")
        assert s["enabled"] and s["damage_scale"] == 1
        assert all(e["suppression"] == 0 and e["peeks"] == 0 for e in s["actors"])
        print("PASS normal restart clears pressure and peek state", flush=True)
    finally:
        game.close_engine()
        game.close()
    errors = [line for line in project.console.read().lines if "ERROR:" in line]
    assert not errors, "\n".join(errors)
    print("PASS clean shutdown", flush=True)


if __name__ == "__main__":
    main()
