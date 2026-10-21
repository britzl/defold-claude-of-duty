"""Build and verify the native game. Run with PYTHONPATH=automation-bridge-python.

Requires the project already open in Defold. Owns and closes the engine it builds.
"""
from pathlib import Path

from automation_bridge import editor, engine


def main():
    project = editor.open_project(Path(__file__).resolve().parents[1], start_if_needed=False)
    game = project.build_and_run(timeout=180, required_capabilities=("application.commands", "input.key>=2"))

    def snapshot():
        return game.command("gameplay.snapshot", {})["result"]

    try:
        # Poll the published state without a blocking native long-poll, so the
        # bridge version bundled with this project can keep advancing loading.
        engine.wait_until(lambda: game.state("world").value["ready"], timeout=20,
                          message="generated world did not finish loading")
        game.command("ai.configure", {"enabled": False})
        world = game.command("world.snapshot", {})["result"]
        assert world["batches"] > 0 and world["colliders"] > 0
        assert world["batches"] < world["boxes"] / 4
        assert world["mesh_bytes"] == world["vertices"] * 40
        validation = game.command("world.validate", {})["result"]
        assert validation["max_error"] < 1e-5
        assert validation["colliders"] == world["colliders"]
        assert all(node["supported"] for node in validation["nodes"])
        assert all(edge["clear"] for edge in validation["edges"])

        def cast(y, z):
            return game.command("world.raycast", {
                "from": {"x": -5.5, "y": y, "z": z},
                "to": {"x": -8, "y": y, "z": z},
            })["result"]

        assert not cast(0.2, 0)["hit"] and not cast(1.9, 0)["hit"]
        assert cast(1.5, 3)["surface"] == "plaster"
        assert cast(3, 0)["id"] == "W2/door_lintel"
        print("PASS world batches, collision dimensions, doorway clearance and navigation")
        print("WORLD", world)

        for key, title in (("F2", "THE SHOPFRONT"), ("F3", "INSIDE W2"), ("F1", "MARKET STREET")):
            game.key(key, wait="released")
            game.wait_for_element(type="gui_node_text", text_exact=title)
        print("PASS three inspection views via native keyboard input")

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

        game.key("0", wait="released")
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
