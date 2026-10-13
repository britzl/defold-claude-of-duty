"""Native tactical sprint, slide, mantle and lean checks.

Run with PYTHONPATH=automation-bridge-python, with this project open in Defold.
Owns and closes the engine it builds.
"""
import math
from pathlib import Path
from automation_bridge import editor, engine


def main():
    project = editor.open_project(Path(__file__).resolve().parents[1], start_if_needed=False)
    game = project.build_and_run(timeout=180, required_capabilities=("application.commands", "input.key>=2"))

    def command(name, data=None):
        return game.command(name, data or {})["result"]

    def reset(x=46, z=2, y=0.01, yaw=0):
        return command("movement.reset", dict(x=x, y=y, z=z, yaw=yaw))

    def drive(segments):
        command("movement.drive", dict(segments=segments))
        def completed():
            result = command("movement.result")
            return result["result"] if result["complete"] else None
        result = engine.wait_until(completed, timeout=25)
        assert not result["recovery_failed"] and result["min_y"] > -0.01, result
        return result

    def run(segments, **position):
        reset(**position)
        return drive(segments)

    sprint = dict(ticks=60, move_z=-1, sprint=True)
    slide = dict(ticks=120, move_z=-1, sprint=True, crouch=True)
    try:
        engine.wait_until(lambda: game.state("world").value["ready"], timeout=20)
        game.command("ai.configure", {"enabled": False})
        command("movement.course")
        game.wait_frames(3)

        tac = run([dict(ticks=12, move_z=-1, sprint=True), dict(ticks=8, move_z=-1),
                   dict(ticks=120, move_z=-1, sprint=True)])
        assert tac["tactical"] and tac["tactical_ticks"] == 120, tac
        assert abs(tac["max_speed"]-8.38) < 0.001, tac
        print("PASS double-tap tactical sprint reaches the source speed")

        burst = run([sprint, slide])
        assert burst["slides"] == 1 and 107 <= burst["slide_ticks"] <= 109 and not burst["sliding"], burst
        assert 8.7 < burst["max_speed"] <= 8.84 and burst["stance"] == "crouch", burst
        wall = run([dict(ticks=30, move_z=-1, sprint=True), slide], x=50, z=0)
        assert wall["slides"] == 1 and wall["z"] >= -3.64 and not wall["sliding"], wall
        ceiling = run([dict(ticks=30, move_z=-1, sprint=True), dict(ticks=60, move_z=-1, sprint=True, crouch=True)], x=86)
        assert ceiling["sliding"] and -6 < ceiling["z"] < -2 and ceiling["height"] == 1.12, ceiling
        assert command("gameplay.snapshot")["camera_y"] < 1.25
        print("PASS bounded slide burst, thin-wall stop and low-ceiling traversal")

        jump = run([sprint, dict(ticks=5, move_z=-1, sprint=True, crouch=True),
                    dict(ticks=100, move_z=-1, jump=True)])
        assert jump["slides"] == 1 and jump["jumps"] == 1 and 7 < jump["slide_jump_speed"] <= 7.431, jump
        assert jump["grounded"] and not jump["sliding"], jump
        print("PASS slide jump preserves bounded momentum and lands")

        for x, z, height, ticks in ((62, -2.4, 0.65, 50), (56, -12.9, 1.2, 110), (62, -12.9, 1.8, 125)):
            result = run([dict(ticks=ticks, move_z=-1, jump=True)], x=x, z=z)
            assert result["mantles"] == result["mantle_completions"] == 1 and result["mantle_aborts"] == 0, result
            assert result["grounded"] and abs(result["y"]-height) < 0.015 and result["jumps"] == 0, result
        crouch = run([dict(ticks=115, move_z=-1, jump=True)], x=86, z=-12.9)
        assert crouch["mantle_completions"] == 1 and crouch["stance"] == "crouch" and crouch["height"] == 1.12, crouch
        assert abs(crouch["y"]-1.2) < 0.015, crouch
        print("PASS low/high mantles and a crouch-only landing")

        for x, z in ((70, -12.9), (78, -12.9), (94, -13.325), (102, -12.9)):
            result = run([dict(ticks=140, move_z=-1, jump=True)], x=x, z=z)
            assert result["mantles"] == 0 and result["y"] < 0.02, result
        stairs = run([dict(ticks=140, move_z=-1)], x=56, z=0)
        assert stairs["mantles"] == 0 and stairs["y"] > 0.59, stairs
        print("PASS tall/roofed/narrow ledges and an obstructed approach reject mantling; stairs remain steps")

        left = run([dict(ticks=90, lean=-1)], z=0)
        right = run([dict(ticks=90, lean=1)], z=0)
        assert left["lean"] < -0.999 and right["lean"] > 0.999
        assert abs(left["x"]-46) < 0.001 and abs(right["x"]-46) < 0.001
        near_wall = run([dict(ticks=90, lean=-1)], x=48.4, z=-2)
        assert -0.54 < near_wall["lean"] < -0.49, near_wall
        approach = run([dict(ticks=60, lean=-1), dict(ticks=100, lean=-1, move_x=-1)], x=49, z=-2)
        assert approach["x"] >= 48.36 and -0.5 < approach["lean"] < -0.3, approach
        state = command("gameplay.snapshot")
        assert state["camera_x"] >= 48.05+0.17, state
        assert abs(state["camera_roll"]) <= math.radians(13)+1e-6
        yawed = run([dict(ticks=90, lean=-1)], z=0, yaw=math.pi/2)
        assert yawed["lean"] < -0.999 and abs(yawed["x"]-46) < 0.001, yawed
        print("PASS both lean directions, body independence and camera clearance while approaching a wall")

        reset()
        receipt = game.key("Q", hold=0.4, wait="started")
        engine.wait_until(lambda: command("gameplay.snapshot")["lean"] < -0.7, timeout=3)
        game.input.wait(receipt, "released")
        engine.wait_until(lambda: abs(command("gameplay.snapshot")["lean"]) < 0.01, timeout=3)
        print("PASS native lean key and return to centre")

        reset(x=56, z=-12.9)
        drive([dict(ticks=1, move_z=-1, jump=True)])
        assert command("gameplay.snapshot")["mantling"]
        command("gameplay.damage", dict(target="player", amount=999))
        engine.wait_until(lambda: not command("gameplay.snapshot")["alive"], timeout=3)
        game.wait_frames(5)
        dead = command("gameplay.snapshot")
        assert not dead["mantling"] and dead["z"] > -13.1, dead
        print("PASS death cancels an in-progress mantle without teleporting to its destination")
    finally:
        game.close_engine()
        game.close()
    errors = [line for line in project.console.read().lines if "ERROR:" in line]
    assert not errors, "\n".join(errors)
    print("PASS clean feature-test shutdown; no runtime errors")


if __name__ == "__main__":
    main()
