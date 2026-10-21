"""Native GUI/gameplay checks through an opt-in touch-action fixture.
macOS does not support Automation Bridge's hardware touch injection.
PYTHONPATH=automation-bridge-python python3 tests/touch_smoke.py
"""
import os
from pathlib import Path
import re
import shutil
import subprocess
import zipfile

from automation_bridge import editor, engine


def main():
    root = Path(__file__).resolve().parents[1]
    output = root / "build" / "touch-validation"
    output.mkdir(parents=True, exist_ok=True)
    result=editor.open_project(root, start_if_needed=False, timeout=5).compile(timeout=120)
    assert result.success,result
    with zipfile.ZipFile(root / ".internal/cache/engine-archives/arm64-osx/build.zip") as archive:
        executable=output / "dmengine"
        executable.write_bytes(archive.read("dmengine"));executable.chmod(0o755)
    with (output / "engine.log").open("w") as log:
        process = subprocess.Popen([
            str(executable), str(root / "build/default/game.projectc"),
            "--config=display.high_dpi=0", "--config=touch_validation.enabled=1", "--config=input_validation.enabled=1",
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
                # Native windows can lose OS focus while this background test
                # runs. Model an active app for taps; test focus loss below.
                cmd("ui.focus", {"focused": True})
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
            cmd("touch_validation.background")
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

            game.wait_frames(30)
            before = cmd("gameplay.snapshot")
            fire = element("touch_fire").bounds.center
            look = element("touch_look").bounds.center
            stick = element("touch_move").bounds
            # Start in empty space and just outside the visible stick, then
            # drag across each control. These gestures must never be captured.
            for x, y in ((10, 20), (stick.center["x"]+stick.w/2+2, stick.center["y"])):
                point(1, x, y, "down")
                point(1, x+20, y+10)
                point(1, look["x"], look["y"])
                point(1, fire["x"], fire["y"])
                point(1, stick.center["x"], stick.center["y"]-stick.h*.48)
                after = cmd("gameplay.snapshot")
                for field in ("x", "z", "yaw", "pitch", "move_x", "move_z"):
                    assert abs(after[field]-before[field]) < 1e-6, (field, before, after)
                assert not cmd("weapons.snapshot")["fired"]
                point(1, x, y, "up")
            point(1, look["x"], look["y"], "down")
            point(1, look["x"]-120, look["y"]-20)
            point(1, look["x"]-120, look["y"]-20, "up")
            assert abs(cmd("gameplay.snapshot")["yaw"]-before["yaw"]) > .01, (look, before, cmd("input_validation.state"))
            assert not cmd("weapons.snapshot")["fired"]
            print("PASS outside touches stay inert; LOOK pad turns without firing", flush=True)

            tap("touch_aim")
            game.wait_frames(30)
            assert cmd("weapons.snapshot")["ads"] > .9
            tap("touch_aim")
            tap("touch_crouch")
            game.wait_frames(30)
            assert cmd("gameplay.snapshot")["stance"] == "crouch"
            tap("touch_crouch")
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
            engine.wait_until(lambda: cmd("weapons.snapshot")["clip"] == "idle", timeout=20)
            tap("touch_next_weapon")
            engine.wait_until(lambda: cmd("weapons.snapshot")["clip"] == "idle", timeout=20)
            assert cmd("weapons.snapshot")["weapon"] != before["weapon"]
            print("PASS touch aim/stances, fire-drag, reload and weapon switch", flush=True)

            for width, height in ((844, 390), (390, 844), (1024, 768)):
                game.resize(width, height)
                game.wait_frames(8)
                cmd("ui.focus", {"focused": True})
                cmd("ui.pause", {"paused": False})
                game.wait_frames(4)
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
            # Mapped controller actions use the real controller script. Hardware
            # mapping itself is covered by the browser Gamepad API fixture.
            def pad(name,value):
                cmd("input_validation.command",{"kind":"inject","name":"pad_"+name,
                    "action":{"gamepad":0,"value":value}})
                game.wait_frames(5)
            cmd("ui.focus", {"focused": True})
            cmd("ui.pause", {"paused": False})
            before=cmd("weapons.snapshot")["fired"]
            pad("move_up",1);pad("look_right",.7);pad("fire",1)
            assert cmd("input_validation.state")["move_z"] < -.9
            assert cmd("weapons.snapshot")["fired"] > before
            pad("pause",1)
            assert cmd("ui.snapshot")["paused"]
            assert not cmd("input_validation.state")["held"].get("fire")
            pad("pause",0);pad("jump",1);pad("jump",0)
            assert not cmd("ui.snapshot")["paused"]
            assert not cmd("input_validation.state")["held"].get("fire")
            pad("move_up",0);pad("look_right",0);pad("fire",0)
            pad("fire",1);pad("disconnected",0)
            assert cmd("ui.snapshot")["paused"]
            assert not cmd("input_validation.state")["held"].get("fire")
            print("PASS native gamepad actions, menu resume, quarantine and disconnect",flush=True)
            tap("tab_controls")
            tap("setting_invert_look")
            assert cmd("ui.snapshot")["input"]["invert_look"]
            bar=element("slider_fov").bounds
            point(1,bar.center["x"]+bar.w*.25,bar.center["y"],"down")
            point(1,bar.center["x"]+bar.w*.25,bar.center["y"],"up")
            assert cmd("ui.snapshot")["input"]["fov"]>85
            tap("defaults")
            assert cmd("ui.snapshot")["input"]["fov"]==70
            assert not cmd("ui.snapshot")["input"]["invert_look"]
            tap("resume")
            game.key("3",wait="released");game.wait_frames(70)
            assert cmd("weapons.snapshot")["weapon"]=="pistol"
            game.key("C",wait="released");game.wait_frames(30)
            assert cmd("gameplay.snapshot")["stance"]=="crouch"
            game.key("Z",wait="released");game.wait_frames(30)
            assert cmd("gameplay.snapshot")["stance"]=="prone"
            game.key("I",wait="released");game.wait_frames(3)
            assert cmd("weapons.snapshot")["clip"]=="inspect"
            print("PASS native keyboard bindings, touch FOV/invert/defaults",flush=True)
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
