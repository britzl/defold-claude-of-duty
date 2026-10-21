"""Native weapon/render/penetration checks. Requires the project open in Defold.
Run: PYTHONPATH=automation-bridge-python python3 tests/weapons_smoke.py
"""
from pathlib import Path
from automation_bridge import editor, engine


def main():
    root = Path(__file__).resolve().parents[1]
    project = editor.open_project(root, start_if_needed=False)
    game = project.build_and_run(timeout=180, required_capabilities=("application.commands", "input.key>=2"))

    def command(name, data=None):
        return game.command(name, data or {})["result"]

    def state():
        return command("weapons.snapshot")

    def idle(weapon=None):
        engine.wait_until(lambda: state()["clip"] == "idle" and (not weapon or state()["weapon"] == weapon),
                          timeout=6, message="weapon did not finish its clip")

    def drive(segments):
        command("weapons.drive", {"segments": segments})
        engine.wait_until(lambda: command("weapons.result")["complete"], timeout=24)
        return command("weapons.result")["result"]

    def reset(x=-5, z=40):
        command("movement.reset", dict(x=x, y=0.01, z=z, yaw=0))
        game.wait_frames(4)

    def shot():
        return drive([dict(ticks=90, aim=True), dict(ticks=1, aim=True, fire=True), dict(ticks=30, aim=True)])

    def capture(name):
        image = game.screenshot(resolution_multiplier=0.5)
        print("SCREENSHOT", name, image.path, flush=True)

    try:
        engine.wait_until(lambda: game.state("world").value["ready"], timeout=20)
        game.command("ai.configure", {"enabled": False})
        idle("rifle")
        assert state()["ammo"] == 31 and state()["reserve"] == 210
        game.wait_for_element(type="gui_node_text", text_exact="M4A1  AUTO  31 / 210")
        capture("rifle_hip")
        targets = command("weapons.range")
        assert len(targets) == 3 and all(v == 1000 for v in targets.values())
        reset()
        bare = shot()
        health = command("weapons.range")
        assert 966 < health["range_target_1"] < 968, health
        assert bare["fired"] == 1 and bare["impacts"] >= 2 and bare["exits"] >= 1, bare
        reset(0)
        wood = shot()
        health = command("weapons.range")
        assert 968 < health["range_target_2"] < 977, health
        assert wood["exits"] >= bare["exits"] + 2, wood
        reset(5)
        concrete = shot()
        assert command("weapons.range")["range_target_3"] == 1000
        assert concrete["fired"] == 3 and concrete["impacts"] > wood["impacts"]
        reset(5, 31.6)
        shot()
        assert command("weapons.range")["range_target_3"] == 1000
        capture("wall_overlap")
        print("PASS native fast segments, wood entry/exit, target damage and concrete/muzzle obstruction", flush=True)

        reset(-5)
        command("weapons.drive", {"segments": [dict(ticks=600, aim=True)]})
        engine.wait_until(lambda: state()["ads"] > 0.999, timeout=3)
        capture("rifle_ads")
        drive([dict(ticks=40)])
        game.key("B", wait="released")
        assert state()["mode"] == "burst"
        before = state()["fired"]
        burst = drive([dict(ticks=120, aim=True, fire=True)])
        assert burst["fired"] == before + 3, burst
        game.key("R", wait="released")
        engine.wait_until(lambda: state()["clip"] == "reloadTac", timeout=3)
        game.wait_frames(35)
        capture("rifle_reload")
        idle()
        assert state()["ammo"] == 31
        print("PASS native ADS, three-shot burst and tactical reload with chambered round", flush=True)

        game.key("2", wait="released")
        idle("smg")
        capture("smg_hip")
        before = state()["fired"]
        smg = drive([dict(ticks=120, fire=True)])
        assert smg["fired"] == before + 16 and smg["ammo"] == 17, smg
        game.key("3", wait="released")
        idle("pistol")
        capture("pistol_hip")
        before = state()["fired"]
        pistol = drive([dict(ticks=120, fire=True)])
        assert pistol["fired"] == before + 1 and pistol["ammo"] == 17, pistol
        pistol = drive([dict(ticks=1), dict(ticks=1, fire=True), dict(ticks=30)])
        assert pistol["fired"] == before + 2 and pistol["ammo"] == 16, pistol
        command("weapons.drive", {"segments": [dict(ticks=600, aim=True)]})
        engine.wait_until(lambda: state()["ads"] > 0.999, timeout=3)
        capture("pistol_ads")
        drive([dict(ticks=40)])
        print("PASS native weapon selection, 950 rpm SMG and edge-triggered pistol", flush=True)

        game.key("1", wait="released")
        idle("rifle")
        assert state()["mode"] == "burst" and state()["ammo"] == 31
        game.key("B", wait="released")
        game.key("B", wait="released")
        assert state()["mode"] == "auto"
        empty = drive([dict(ticks=350, fire=True)])
        assert empty["ammo"] == 0 and not empty["chambered"] and empty["clip"] == "idle", empty
        reserve = empty["reserve"]
        game.key("R", wait="released")
        engine.wait_until(lambda: state()["clip"] == "reloadEmpty", timeout=3)
        idle()
        assert state()["ammo"] == 30 and state()["reserve"] == reserve - 30 and state()["chambered"]
        game.key("F", wait="released")
        engine.wait_until(lambda: state()["clip"] == "inspect", timeout=3)
        game.wait_frames(25)
        capture("rifle_inspect")
        before = state()["fired"]
        fired = drive([dict(ticks=1, fire=True), dict(ticks=30)])
        assert fired["fired"] == before + 1 and fired["clip"] == "idle"
        print("PASS native empty reload, independent inventories and interruptible inspection", flush=True)

        game.key("F1", wait="released")
        before = state()["fired"]
        game.wait_frames(5)
        capture("inspection_world_only")
        assert state()["fired"] == before
        game.key("0", wait="released")
        command("gameplay.damage", {"target": "player", "amount": 999})
        engine.wait_until(lambda: not command("gameplay.snapshot")["alive"], timeout=3)
        dead = drive([dict(ticks=60, fire=True, reload=True)])
        assert dead["fired"] == before and dead["clip"] == "idle", dead
        print("PASS inspection camera and death suppress weapon rendering/actions", flush=True)
    finally:
        game.close_engine()
        game.close()
    errors = [line for line in project.console.read().lines if "ERROR:" in line]
    assert not errors, "\n".join(errors)
    print("PASS clean weapon-test shutdown; no runtime errors", flush=True)


if __name__ == "__main__":
    main()
