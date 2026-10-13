"""Native Bullet traversal regression. Run with PYTHONPATH=automation-bridge-python.

Requires this project open in Defold; owns and closes the engine it builds.
Every drive runs through real fixed_update calls, including Defold physics.
"""
import math
from pathlib import Path

from automation_bridge import editor, engine


def main():
    project = editor.open_project(Path(__file__).resolve().parents[1], start_if_needed=False)
    game = project.build_and_run(timeout=180, required_capabilities=("application.commands", "input.key>=2"))

    def command(name, data=None):
        return game.command(name, data or {})["result"]

    def drive(segments):
        command("movement.drive", {"segments": segments})
        def completed():
            state = command("movement.result")
            return state if state["complete"] else None
        result = engine.wait_until(completed,
                                   timeout=25, message="movement drive did not finish")
        result = result["result"]
        assert not result["recovery_failed"], result
        assert result["min_y"] > -0.01, result
        return result

    def run(x, segments, *, y=0.01, z=0, yaw=0, velocity=None):
        reset = dict(x=x, y=y, z=z, yaw=yaw)
        if velocity:
            reset["velocity"] = velocity
        command("movement.reset", reset)
        return drive(segments)

    def near(value, expected, tolerance):
        assert abs(value-expected) < tolerance, (value, expected, tolerance)

    try:
        engine.wait_until(lambda: game.state("world").value["ready"], timeout=20)
        game.command("ai.configure", {"enabled": False})
        command("movement.course")
        game.wait_frames(3)  # Factory-created course bodies enter the broadphase.

        walk = run(46, [dict(ticks=120, move_z=-1)])
        repeat = run(46, [dict(ticks=120, move_z=-1)])
        sprint = run(46, [dict(ticks=120, move_z=-1, sprint=True)])
        diagonal = run(56, [dict(ticks=120, move_x=-1, move_z=-1)], z=3)
        near(walk["z"], -4.4754, 0.02)
        near(repeat["z"], walk["z"], 0.001)
        near(sprint["z"], -6.7718, 0.02)
        assert math.hypot(diagonal["x"]-56, diagonal["z"]-3) <= abs(walk["z"])+0.01
        print("PASS fixed-tick walking, sprint speed, repeatability and diagonal normalization")

        jump = run(46, [dict(ticks=12), dict(ticks=120, jump=True)])
        assert jump["jumps"] == 1 and jump["landings"] == 1 and jump["grounded"], jump
        near(jump["max_y"], 0.6, 0.025)
        print("PASS jump apex, landing and no repeated jump from one input edge")

        wall = run(50, [dict(ticks=150, move_z=-1)])
        corner = run(50, [dict(ticks=180, move_x=-1, move_z=-1)])
        fast = run(50, [dict(ticks=12)], z=-2, velocity=dict(z=-200))
        overlap = run(50, [dict(ticks=30)], z=-3.8)
        for result in (wall, corner, fast, overlap):
            assert result["z"] >= -3.64 and result["grounded"], result
        near(corner["x"], 48.374, 0.025)
        print("PASS wall sliding, inside corner, overlap recovery and 200 m/s thin-wall sweep")

        stairs = run(56, [dict(ticks=140, move_z=-1), dict(ticks=12)])
        assert stairs["z"] < -5.1 and stairs["grounded"], stairs
        near(stairs["y"], 0.604, 0.01)
        down = run(56, [dict(ticks=150, move_z=-1)], y=0.61, z=-5.5, yaw=math.pi)
        assert down["z"] > -0.1 and down["grounded"], down
        high = run(62, [dict(ticks=150, move_z=-1)])
        assert high["z"] > -2.7 and high["max_y"] < 0.02, high
        print("PASS three 20 cm stairs up/down and rejection of a 65 cm step")

        slope = run(70, [dict(ticks=170, move_z=-1), dict(ticks=12)])
        assert slope["z"] < -5.8 and slope["y"] > 2 and slope["grounded"], slope
        assert slope["grounded_ticks"] >= slope["ticks"]-2, slope
        down = run(70, [dict(ticks=180, move_z=-1)], y=3.01, z=-7.25, yaw=math.pi)
        assert down["y"] < 0.02 and down["grounded_ticks"] >= down["ticks"]-2, down
        steep = run(78, [dict(ticks=150, move_z=-1)])
        assert steep["z"] > -3.3 and steep["max_y"] < 0.02, steep
        fall = run(78, [dict(ticks=240)], y=4, z=-5)
        assert fall["grounded"] and fall["y"] < 0.02 and fall["z"] > -3.2, fall
        print("PASS grounded 30-degree ramp traversal, 60-degree slope rejection and downhill falling")

        crouch = run(86, [dict(ticks=180, move_z=-1, crouch=True), dict(ticks=24)])
        assert -5 < crouch["z"] < -3 and crouch["stance"] == "crouch", crouch
        near(crouch["height"], 1.12, 0.001)
        head = drive([dict(ticks=12, crouch=True), dict(ticks=90, crouch=True, jump=True)])
        assert head["jumps"] == 1 and head["max_y"]+head["height"] < 1.251, head
        prone = drive([dict(ticks=120, move_z=-1, prone=True, jump=True)])
        assert prone["stance"] == "prone" and prone["jumps"] == 0, prone
        near(prone["height"], 0.7, 0.001)
        blocked = drive([dict(ticks=12)])
        assert blocked["stance"] == "prone", blocked
        stand = drive([dict(ticks=220, move_z=1, crouch=True), dict(ticks=24)])
        assert stand["stance"] == "stand" and stand["height"] == 1.78, stand
        print("PASS crouch/prone clearance, blocked standing, ceiling jump and standing after exit")

        narrow = run(94, [dict(ticks=150, move_z=-1)])
        wide = run(102, [dict(ticks=150, move_z=-1)])
        assert narrow["z"] > -3.8 and wide["z"] < -5.5, (narrow, wide)
        room = run(-3, [dict(ticks=240, move_z=-1)], yaw=math.pi/2)
        assert room["x"] < -10 and room["grounded"], room
        near(room["y"], 0.145, 0.01)
        print("PASS capsule width clearance and street-to-room traversal over the kerb")

        command("world.view", {"name": "street"})
        game.key("0", wait="released")
        game.wait_for_element(type="gui_node_text", text_exact="STAND")
        before = command("gameplay.snapshot")
        receipt = game.key("W", hold=0.5, wait="started")
        game.input.wait(receipt, "released")
        after = command("gameplay.snapshot")
        assert after["x"] < before["x"]-1, (before, after)
        print("PASS native keyboard returns from inspection and moves the capsule")
        game.click(480, 320, device="mouse")
        locked = command("gameplay.snapshot")
        assert locked["mouse_locked"]
        game.key("ESCAPE", wait="released")
        assert not command("gameplay.snapshot")["mouse_locked"]
        # Bridge pointer drags send bound button actions; the camera consumes
        # Defold's separate, unbound mouse-motion action. Drive its normalized
        # deltas to verify look through the native simulation deterministically.
        looked = run(46, [dict(ticks=1, look_x=100, look_y=1000)])
        near(looked["yaw"], -0.22, 1e-6)
        near(looked["pitch"], math.radians(88), 1e-6)
        print("PASS native mouse capture/release and fixed-tick look/pitch limit")
        command("movement.reset", dict(x=0, y=0.01, z=10))
        game.wait_frames(3)
        print("SCREENSHOT", game.screenshot(resolution_multiplier=0.5).path)
    finally:
        game.close_engine()
        game.close()
    errors = [line for line in project.console.read().lines if "ERROR:" in line]
    assert not errors, "\n".join(errors)
    print("PASS clean traversal course teardown; no runtime errors")


if __name__ == "__main__":
    main()
