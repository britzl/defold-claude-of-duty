"""Native GUI/gameplay checks through an opt-in touch-action fixture.
macOS does not support Automation Bridge's hardware touch injection.
PYTHONPATH=automation-bridge-python python3 tests/touch_smoke.py
"""
import os
from pathlib import Path
import re
import shutil
import subprocess

from automation_bridge import editor, engine


def main():
    root = Path(__file__).resolve().parents[1]
    output = root / "build" / "touch-validation"
    output.mkdir(parents=True, exist_ok=True)
    editor.open_project(root, start_if_needed=False, timeout=5).compile(timeout=120)
    with (output / "engine.log").open("w") as log:
        process = subprocess.Popen([
            str(root / "build/arm64-osx/dmengine"), str(root / "build/default/game.projectc"),
            "--config=display.high_dpi=0", "--config=touch_validation.enabled=1",
        ], cwd=root, stdout=log, stderr=subprocess.STDOUT, env={**os.environ, "DM_SERVICE_PORT": "dynamic"})
        game = None
        try:
            def ready_port():
                assert process.poll() is None, (output / "engine.log").read_text()
                match = re.search(r"Engine service started on port (\d+)", (output / "engine.log").read_text())
                return int(match[1]) if match else None

            game = engine.connect(engine.wait_until(ready_port, timeout=20), timeout=30)

            def cmd(name, data=None):
                return game.command(name, data or {})["result"]

            def element(name):
                return game.element(name_exact=name, visible=True)

            def tap(name):
                center = element(name).bounds.center
                point(1, center["x"], center["y"], "down")
                point(1, center["x"], center["y"], "up")
                game.wait_frames(4)

            def point(touch_id, x, y, phase=None):
                cmd("touch_validation.input", {"points": [{"id": touch_id, "x": x, "y": y,
                    "pressed": phase == "down", "released": phase == "up"}]})
                game.wait_frames(2)

            def capture(name):
                shutil.copyfile(game.screenshot().path, output / (name + ".png"))

            engine.wait_until(lambda: cmd("world.snapshot")["ready"], timeout=30)
            engine.wait_until(lambda: cmd("renderer.snapshot")["ready"], timeout=30)
            cmd("ai.configure", {"enabled": False})
            cmd("ui.focus", {"focused": True})
            cmd("ui.pause", {"paused": False})
            assert not cmd("ui.snapshot")["touch_controls"]
            cmd("touch_validation.input", {"mouse": True})
            point(1, 480, 320, "down")
            point(1, 480, 320, "up")
            game.wait_frames(5)
            assert cmd("ui.snapshot")["touch_controls"]
            assert not cmd("gameplay.snapshot")["mouse_locked"]
            assert not cmd("weapons.snapshot")["fired"]
            capture("controls_960x640")
            print("PASS first touch enables controls without mouse lock or accidental fire", flush=True)

            tap("touch_aim")
            game.wait_frames(30)
            assert cmd("weapons.snapshot")["ads"] > .9
            tap("touch_aim")
            tap("touch_crouch")
            game.wait_frames(30)
            assert cmd("gameplay.snapshot")["stance"] == "crouch"
            tap("touch_prone")
            game.wait_frames(30)
            assert cmd("gameplay.snapshot")["stance"] == "prone"
            tap("touch_prone")
            game.wait_frames(30)
            assert cmd("gameplay.snapshot")["stance"] == "stand"

            before = cmd("weapons.snapshot")
            fire = element("touch_fire").bounds.center
            point(1, fire["x"], fire["y"], "down")
            point(1, fire["x"]+30, fire["y"]+10)
            game.wait_frames(30)
            point(1, fire["x"]+30, fire["y"]+10, "up")
            after = cmd("weapons.snapshot")
            assert after["fired"] > before["fired"]
            assert abs(cmd("gameplay.snapshot")["yaw"]) > .01
            tap("touch_reload")
            assert cmd("weapons.snapshot")["clip"] in ("reloadTac", "reloadEmpty")
            game.wait_frames(200)
            tap("touch_next_weapon")
            game.wait_frames(100)
            assert cmd("weapons.snapshot")["weapon"] != before["weapon"]
            print("PASS touch aim/stances, fire-drag, reload and weapon switch", flush=True)

            for width, height in ((844, 390), (390, 844), (1024, 768)):
                game.resize(width, height)
                game.wait_frames(8)
                capture(f"controls_{width}x{height}")
                tap("touch_pause")
                assert cmd("ui.snapshot")["paused"]
                tap("tab_controls")
                capture(f"menu_{width}x{height}")
                tap("tab_audio")
                bar = element("slider_master").bounds
                cx, cy = bar.center["x"], bar.center["y"]
                point(1, cx-bar.w*.25, cy, "down")
                point(1, cx+bar.w*.25, cy)
                point(1, cx+bar.w*.25, cy, "up")
                game.wait_frames(4)
                assert .73 < cmd("ui.snapshot")["audio"]["master"] < .81
                tap("resume")
                assert not cmd("ui.snapshot")["paused"]
                assert not cmd("gameplay.snapshot")["mouse_locked"]
            print("PASS touch pause/resume and slider dragging at phone/tablet aspects", flush=True)

            game.resize(960, 640)
            game.wait_frames(8)
            stick = element("touch_move").bounds
            cx, cy = stick.center["x"], stick.center["y"]
            point(1, cx, cy, "down")
            point(1, cx, cy-stick.h*.48)
            game.wait_frames(30)
            assert cmd("gameplay.snapshot")["move_z"] < -.9
            cmd("ui.focus", {"focused": False})
            game.wait_frames(4)
            assert cmd("gameplay.snapshot")["move_z"] == 0
            point(1, cx, cy, "up")
            cmd("ui.focus", {"focused": True})
            assert cmd("ui.snapshot")["paused"]
            tap("restart")
            game.wait_frames(10)
            assert not cmd("ui.snapshot")["paused"]
            assert cmd("gameplay.snapshot")["move_z"] == 0
            cmd("gameplay.damage", {"target": "player", "amount": 1000})
            game.wait_frames(10)
            assert not cmd("gameplay.snapshot")["alive"]
            tap("touch_pause")
            tap("restart")
            game.wait_frames(10)
            assert cmd("gameplay.snapshot")["alive"]
            print("PASS analog movement, focus reset, death menu and restart", flush=True)
        finally:
            if game:
                game.close_engine()
                game.close()
            if process.poll() is None:
                process.terminate()
            process.wait(timeout=10)
    errors = [line for line in (output / "engine.log").read_text().splitlines() if "ERROR:" in line]
    assert not errors, "\n".join(errors)


if __name__ == "__main__":
    main()
