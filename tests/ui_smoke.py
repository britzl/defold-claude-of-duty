"""Native HUD/menu/input checks. Owns the engine; saves build/ui-validation images.
PYTHONPATH=automation-bridge-python python3 tests/ui_smoke.py
"""
import math
import shutil
from pathlib import Path
from automation_bridge import editor, engine


def main():
    root = Path(__file__).resolve().parents[1]
    output = root / "build" / "ui-validation"
    output.mkdir(parents=True, exist_ok=True)
    project = editor.open_project(root, start_if_needed=False)
    game = project.build_and_run(timeout=180)

    def cmd(name, data=None):
        return game.command(name, data or {})["result"]

    def ui():
        return cmd("ui.snapshot")

    def key(name):
        game.key(name, wait="released")
        game.wait_frames(2)

    def click(name):
        game.click(game.element(name_exact=name, visible=True))
        game.wait_frames(3)

    def capture(name):
        shot = game.screenshot(resolution_multiplier=1)
        shutil.copyfile(shot.path, output / (name + ".png"))

    def pause(value):
        cmd("ui.pause", {"paused": value})
        game.wait_frames(3)
        assert ui()["paused"] == value

    try:
        engine.wait_until(lambda: game.state("world").value["ready"], timeout=25)
        engine.wait_until(lambda: cmd("renderer.snapshot")["ready"], timeout=5)
        cmd("ai.configure", {"enabled": False})
        game.wait_frames(40)
        assert ui()["map_rectangles"] == 36
        assert game.element(name_exact="map_player", visible=True)
        assert game.element(name_exact="health", visible=True).text == "HEALTH 100"
        capture("hud_street")
        cmd("movement.reset", {"x": -10, "y": .15, "z": 0, "yaw": -math.pi/2})
        game.wait_frames(5)
        assert abs(ui()["hud"]["heading"] - 90) < .01
        assert game.element(name_exact="heading", visible=True).text == "090"
        capture("hud_room_east")
        print("PASS world minimap, player marker and compass", flush=True)

        cmd("gameplay.restart")
        # Let the real AI run, then freeze it together with the clock and rounds.
        game.wait_frames(40)
        key("ESC")
        assert ui()["paused"] and not cmd("gameplay.snapshot")["mouse_locked"]
        before, enemy = cmd("gameplay.snapshot"), cmd("ai.snapshot")
        weapon = cmd("weapons.snapshot")
        cmd("gameplay.damage", {"target": "player", "amount": 5})
        game.wait_frames(45)
        after = cmd("gameplay.snapshot")
        for field in ("tick", "elapsed", "health", "x", "y", "z", "camera_x", "camera_y", "camera_z"):
            assert before[field] == after[field], (field, before[field], after[field])
        assert cmd("ai.snapshot")["actors"] == enemy["actors"]
        assert cmd("weapons.snapshot") == weapon
        assert cmd("audio.snapshot")["suspended"]
        engine.wait_until(lambda: cmd("audio.snapshot")["active"] == 0, timeout=4)
        capture("pause_audio")
        print("PASS Escape pauses native AI, damage, clock, weapons and sound", flush=True)

        # Use the native GUI hit targets, not the settings command.
        click("slider_master")
        assert abs(ui()["audio"]["master"] - .5) <= .02, ui()
        key("RIGHT")
        assert abs(ui()["audio"]["master"] - .55) <= .02, ui()
        # Drag across the actual bar with the pointer held down.
        bar = game.element(name_exact="slider_master").bounds
        cx, cy = bar.center["x"], bar.center["y"]
        game.drag((cx - bar.w * .25, cy), (cx + bar.w * .25, cy), duration=.4)
        game.wait_frames(3)
        assert .74 < ui()["audio"]["master"] < .81, ui()
        for name in ("weapons", "foley", "ambience"):
            click("slider_" + name)
            assert abs(ui()["audio"][name] - .5) <= .02
        click("setting_muted")
        assert ui()["audio"]["muted"]
        click("setting_muted")
        click("tab_display")
        for name in ("shadows", "normal_maps", "local_lights", "fog", "bloom"):
            click("setting_" + name)
            assert ui()["renderer"][name] is False
            engine.wait_until(lambda: cmd("renderer.snapshot")["settings"][name] is False, timeout=3)
            click("setting_" + name)
        click("slider_exposure")
        assert abs(ui()["renderer"]["exposure"] - 2.13) <= .03
        click("setting_view")
        assert ui()["renderer"]["view"] == "albedo"
        key("LEFT")
        assert ui()["renderer"]["view"] == "scene"
        capture("pause_display")
        click("tab_controls")
        click("slider_sensitivity")
        assert abs(ui()["sensitivity"] - 1.63) <= .03
        capture("pause_controls")
        print("PASS native audio sliders/mute, renderer controls and mouse sensitivity", flush=True)

        # UI hit tests and slider conversion must track non-native aspect ratios.
        for width, height in ((800, 500), (640, 900), (1280, 600)):
            game.resize(width, height)
            game.wait_frames(5)
            click("tab_audio")
            click("slider_master")
            assert abs(ui()["audio"]["master"] - .5) <= .02, (width, height, ui())
            # Every map rectangle must stay inside the map after anchoring.
            border = game.element(name_exact="map_background").bounds
            for index in range(1, 37):
                node = game.maybe_element(name_exact=f"map_{index}", visible=True)
                if node:
                    b = node.bounds
                    assert b.x >= border.x - 1 and b.y >= border.y - 1, (width, height, index, b, border)
                    assert b.x + b.w <= border.x + border.w + 1
                    assert b.y + b.h <= border.y + border.h + 1
            capture(f"pause_{width}x{height}")
        game.resize(960, 640)
        game.wait_frames(5)
        # Rebuild each tab repeatedly; the live node count must remain bounded.
        nodes = game.count(type="gui_node_box") + game.count(type="gui_node_text")
        for _ in range(3):
            for tab in ("display", "controls", "audio"):
                click("tab_" + tab)
        assert game.count(type="gui_node_box") + game.count(type="gui_node_text") == nodes
        click("resume")
        assert not ui()["paused"]
        cmd("ai.configure", {"enabled": False})
        assert cmd("gameplay.snapshot")["health"] <= before["health"] - 5
        # Resume and first capture clicks cannot shoot. The following click can.
        ammo = cmd("weapons.snapshot")["ammo"]
        game.click(480, 320)
        game.wait_frames(4)
        assert cmd("gameplay.snapshot")["mouse_locked"]
        assert cmd("weapons.snapshot")["ammo"] == ammo
        game.click(480, 320)
        game.wait_frames(4)
        assert cmd("weapons.snapshot")["ammo"] < ammo
        print("PASS resize, resume, mouse capture and no accidental first shot", flush=True)

        # A held movement key is quarantined until released, even across resume.
        held = game.key("W", hold=2, wait="started")
        game.wait_frames(3)
        assert cmd("gameplay.snapshot")["move_z"] == -1
        pause(True)
        pause(False)
        game.wait_frames(3)
        assert cmd("gameplay.snapshot")["move_z"] == 0
        game.input.wait(held, "released")
        key("R")
        pause(True)
        clip = cmd("weapons.snapshot")
        assert clip["clip"] in ("reloadTac", "reloadEmpty")
        game.wait_frames(30)
        assert cmd("weapons.snapshot")["progress"] == clip["progress"]
        key("ESC")
        engine.wait_until(lambda: cmd("weapons.snapshot")["clip"] == "idle", timeout=6)
        print("PASS held movement does not stick and paused reload resumes", flush=True)

        cmd("movement.reset", {"x": 0, "y": .01, "z": 10, "yaw": 0})
        cmd("renderer.configure", {"exposure": 1})
        cmd("gameplay.damage", {"target": "enemy_1", "source": "player", "amount": 999, "headshot": True})
        game.wait_frames(3)
        assert "YOU  >  HOSTILE  [HEAD]" in ui()["hud"]["feed"]
        capture("killfeed")
        for _ in range(3):
            cmd("ai.reset")
            cmd("gameplay.damage", {"target": "enemy_1", "source": "player", "amount": 999})
            game.wait_frames(2)
        assert ui()["hud"]["feed_count"] == 4
        capture("killfeed_full")
        cmd("gameplay.damage", {"target": "player", "source": "enemy_1", "amount": 10})
        game.wait_frames(2)
        assert ui()["hud"]["damage"] > 0 and ui()["hud"]["damage_direction"]
        capture("damage")
        cmd("gameplay.damage", {"target": "player", "amount": 999})
        game.wait_for_element(name_exact="death", text_exact="YOU WERE ELIMINATED", visible=True)
        key("ESC")
        saved = ui()
        # Keyboard default focus is Resume, Down selects Restart.
        key("DOWN")
        key("ENTER")
        game.wait_frames(4)
        assert not ui()["paused"] and cmd("gameplay.snapshot")["health"] == 100
        assert ui()["hud"]["feed_count"] == 0
        assert ui()["audio"] == saved["audio"] and ui()["sensitivity"] == saved["sensitivity"]
        assert ui()["renderer"] == saved["renderer"]
        print("PASS killfeed, directional damage, death, keyboard restart and retained settings", flush=True)
    finally:
        game.close_engine()
        game.close()
    errors = [line for line in project.console.read().lines if "ERROR:" in line]
    assert not errors, "\n".join(errors)
    print("PASS clean native shutdown with no runtime errors", flush=True)


if __name__ == "__main__":
    main()
