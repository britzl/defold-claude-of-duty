"""Build and verify the native game. Run with PYTHONPATH=automation-bridge-python.

Requires the project already open in Defold. Owns and closes the engine it builds.
"""
from pathlib import Path

from automation_bridge import editor


def main():
    project = editor.open_project(Path(__file__).resolve().parents[1], start_if_needed=False)
    game = project.build_and_run(timeout=180, required_capabilities=("application.commands", "input.key>=2"))

    def snapshot():
        return game.command("gameplay.snapshot", {})["result"]

    try:
        start = snapshot()
        assert start["physics"] == "3D" and start["physics_scale"] == 1
        assert abs(start["gravity"] + 20.6) < 1e-5
        assert abs(start["fixed_dt"] - 1 / 120) < 1e-8
        assert start["health"] == 100
        game.wait_frames(30)
        end = snapshot()
        assert end["tick"] > start["tick"] and 0 <= end["alpha"] <= 1
        sim_delta = end["elapsed"] - start["elapsed"]
        frame_delta = end["frame_elapsed"] - start["frame_elapsed"]
        assert abs(sim_delta - frame_delta) < 2 / 120
        print("PASS native fixed clock, Bullet configuration and initialization")

        receipt = game.key("W", hold=1, wait="started")
        game.wait_frames(2)
        assert snapshot()["move_z"] == -1
        game.input.wait(receipt, "released")
        game.wait_frames(2)
        assert snapshot()["move_z"] == 0
        print("PASS native key input reaches simulation and releases")

        hit = game.command("gameplay.damage", {"target": "player", "amount": 25})["result"]
        assert hit["accepted"]
        game.wait_for_element(type="gui_node_text", text_exact="HEALTH 75")
        assert snapshot()["health"] == 75
        game.wait_frames(5)
        assert snapshot()["health"] == 75
        print("PASS queued damage applies once and updates HUD")

        shot = game.screenshot(resolution_multiplier=0.5)
        print("SCREENSHOT", shot.path)

        game.command("gameplay.damage", {"target": "player", "amount": 999})
        game.wait_for_element(type="gui_node_text", text_exact="HEALTH 0")
        assert not snapshot()["alive"]
        hit = game.command("gameplay.damage", {"target": "player", "amount": 1})["result"]
        assert not hit["accepted"]
        print("PASS overkill clamps health and dead actors reject hits")
    finally:
        game.close_engine()
        game.close()

    errors = [line for line in project.console.read().lines if "ERROR:" in line]
    assert not errors, "\n".join(errors)
    print("PASS clean engine shutdown; no runtime errors")


if __name__ == "__main__":
    main()
