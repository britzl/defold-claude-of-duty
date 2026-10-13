"""Native W2 floor/door/guard collision, player traversal and layered AI routes.
Run with PYTHONPATH=automation-bridge-python; owns the engine it builds.
"""
import argparse
import math
import shutil
import time
from pathlib import Path
from automation_bridge import editor, engine


def main(ai_only=False):
    root = Path(__file__).resolve().parents[1]
    output = root / "build" / "building-validation"
    output.mkdir(parents=True, exist_ok=True)
    project = editor.open_project(root, start_if_needed=False)
    game = project.build_and_run(timeout=180)

    def cmd(name, data=None):
        return game.command(name, data or {})["result"]

    def player():
        return cmd("gameplay.snapshot")

    def soldier():
        keep_running()
        return cmd("ai.snapshot")["actors"][0]

    def keep_running():
        # Exercise simulation in the background without stealing desktop focus.
        # This calls the same focus callback as the window, then explicitly resumes.
        if cmd("ui.snapshot")["paused"]:
            cmd("ui.focus", {"focused": True})
            cmd("ui.pause", {"paused": False})

    def drive(segments):
        keep_running()
        cmd("movement.drive", {"segments": segments})
        def completed():
            keep_running()
            return cmd("movement.result")["complete"]
        engine.wait_until(completed, timeout=25)
        result = cmd("movement.result")["result"]
        assert not result["recovery_failed"] and result["jumps"] == 0, result
        return result

    def walk_to(point):
        for _ in range(100):
            p = player()
            dx, dz = point["x"]-p["x"], point["z"]-p["z"]
            distance = math.hypot(dx, dz)
            if distance < .13:
                drive([dict(ticks=12)])
                p = player()
                assert abs(p["y"]-point["y"]) < .08, (point, p)
                assert p["grounded"], p
                return
            speed = min(3, distance*3)
            drive([dict(ticks=24, move_x=dx/distance*speed/(4.57*.92),
                        move_z=dz/distance*speed/(4.57*(.8 if dz > 0 else 1)))])
        raise AssertionError(("Player stuck", point, player()))

    def capture(name):
        game.wait_frames(4)
        shot = game.screenshot(resolution_multiplier=.75)
        shutil.copyfile(shot.path, output / (name+".png"))
        print("SCREENSHOT", output / (name+".png"), flush=True)

    try:
        engine.wait_until(lambda: game.state("world").value["ready"], timeout=25)
        engine.wait_until(lambda: len(cmd("ai.snapshot")["actors"]) == 1, timeout=5)
        cmd("ai.configure", {"enabled": False})
        nav = cmd("world.navigation")
        nodes = {n["id"]: n for n in nav["nodes"]}
        valid = cmd("world.validate")
        assert valid["max_error"] < 1e-5 and all(n["supported"] for n in valid["nodes"]), valid
        assert all(e["clear"] for e in valid["edges"]), valid
        assert cmd("ui.snapshot")["map_rectangles"] == cmd("world.snapshot")["colliders"]
        if not ai_only:
            route_names = ["room", "W2/stair_approach", "W2/stair_bottom", "W2/stair_top",
                           "W2/upper_hall", "W2/upper_room", "W2/bedroom"]
            cmd("movement.reset", dict(x=-5.5, y=.15, z=0, yaw=0))
            for name in route_names:
                walk_to(nodes[name])
                print("PASS player reached", name, flush=True)
            capture("upstairs_player")
            for name in reversed(route_names[:-1]):
                walk_to(nodes[name])
            walk_to(dict(x=-5.5, y=.145, z=0))
            print("PASS continuous street-to-bedroom-and-back walk with standing headroom and no jumps", flush=True)

            # The side guard prevents an upper-floor sideways walk into the stair hole.
            cmd("movement.reset", dict(x=-16.7, y=3.35, z=-1, yaw=0))
            guard = drive([dict(ticks=160, move_x=-1), dict(ticks=12)])
            assert guard["x"] > -17.6 and guard["y"] > 3.3, guard
            # Solid floor and roof remain separate from the stair hole.
            hit = cmd("world.raycast", {"from": dict(x=-12, y=5, z=-3), "to": dict(x=-12, y=1, z=-3)})
            assert hit["id"] == "W2/upper/floor/east" and abs(hit["y"]-3.345) < .001, hit
            print("PASS upper guard and floor collision", flush=True)
            # This used to snap through the first rounded edge at patrol speed.
            cmd("movement.reset", dict(x=-19.2, y=.15, z=2.25, yaw=0))
            slow = drive([dict(ticks=960, move_z=-1.1/4.57), dict(ticks=24)])
            assert slow["y"] > 3.3 and slow["z"] < -5.3, slow
            # Brief corner contacts may be airborne for a few fixed ticks;
            # repeated floor snaps previously produced dozens of landings and no ascent.
            assert slow["grounded"] and slow["grounded_ticks"] >= slow["ticks"]*.99 and slow["landings"] <= 3, slow
            print("PASS slow capsule climbs all sixteen treads without repeated floor snaps", flush=True)

        # Keep the player out of sight so actual patrol locomotion exercises the entire route.
        cmd("movement.reset", dict(x=0, y=.01, z=10, yaw=0))
        cmd("ai.reset", {"position": dict(x=-9.5, y=.15, z=0), "yaw": 0})
        game.wait_frames(4)
        upper = nodes["W2/bedroom"]
        route = cmd("ai.route", {"target": upper})["points"]
        assert route and any(.4 < p["y"] < 3.2 for p in route), route
        assert any(p["x"] < -18 for p in route), route
        cmd("ai.patrol", {"points": [upper]})
        cmd("ai.configure", {"enabled": True})
        progress = [0]
        def upstairs():
            e = soldier()
            if time.monotonic()-progress[0] > 8:
                progress[0] = time.monotonic()
                print("AI ascent", {k:e[k] for k in ("x", "y", "z", "state", "route", "travel")}, flush=True)
            return math.dist([e[k] for k in ("x", "y", "z")], [upper[k] for k in ("x", "y", "z")]) < .5
        engine.wait_until(upstairs,
                          timeout=55, message="Enemy did not reach bedroom")
        assert not soldier()["recovery_failed"], soldier()
        print("PASS native enemy climbs stairs and enters bedroom", soldier(), flush=True)
        lower = nodes["room"]
        route = cmd("ai.route", {"target": lower})["points"]
        assert route and any(.4 < p["y"] < 3.2 for p in route), route
        cmd("ai.patrol", {"points": [lower]})
        engine.wait_until(lambda: soldier()["y"] < .2 and soldier()["x"] > -10,
                          timeout=55, message="Enemy did not return to shop")
        assert not soldier()["recovery_failed"], soldier()
        print("PASS native enemy descends stairs and returns to shop", flush=True)

        # A real player hit supplies last-seen position. The floor/guard hide
        # the upstairs player until the enemy pursues through the staircase.
        cmd("ai.configure", {"enabled": False})
        cmd("movement.reset", dict(x=-9, y=3.35, z=-5.55, yaw=0))
        cmd("ai.reset", {"position": nodes["W2/stair_bottom"], "yaw": 0})
        game.wait_frames(4)
        cmd("gameplay.damage", dict(target="enemy_1", amount=1, source="player"))
        cmd("ai.configure", {"enabled": True})
        engine.wait_until(lambda: soldier()["state"] == "pursuit", timeout=3)
        engine.wait_until(lambda: soldier()["y"] > 3.3, timeout=9,
                          message="Alerted enemy did not pursue upstairs")
        assert not soldier()["recovery_failed"], soldier()
        print("PASS alerted enemy pursues the player onto the upper floor", soldier(), flush=True)
        for name in ("stairs", "upstairs"):
            cmd("world.view", {"name": name})
            capture(name)
        print("WORLD", cmd("world.snapshot"), flush=True)
    except Exception:
        print("FAILED STATE", cmd("ai.snapshot"), cmd("ui.snapshot"), flush=True)
        print("FAILED ROUTE", cmd("ai.route", {"target": nodes["W2/bedroom"]}), flush=True)
        raise
    finally:
        game.close_engine()
        game.close()
    errors = [line for line in project.console.read().lines if "ERROR:" in line]
    assert not errors, "\n".join(errors)
    print("PASS clean building-test shutdown", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--ai-only", action="store_true", help="Run just the native navigation/combat checks")
    main(parser.parse_args().ai_only)
