"""Native W2/E2 floor collision, continuous player traversal and layered AI routes.
Run with PYTHONPATH=automation-bridge-python; owns the engine it builds.
"""
import argparse
import math
import shutil
import time
from pathlib import Path
from automation_bridge import editor, engine
from world_navigation import read_navigation


def main(ai_only=False, e2_only=False, w2_only=False):
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
        engine.wait_until(lambda: len(cmd("ai.snapshot")["actors"]) == 6, timeout=5)
        errors = [line for line in project.console.read().lines if "ERROR:" in line]
        assert not errors, "\n".join(errors)
        cmd("ai.configure", {"enabled": False})
        nav = read_navigation(cmd)
        nodes = {n["id"]: n for n in nav["nodes"]}
        valid = cmd("world.validate")
        assert valid["max_error"] < 1e-5 and all(n["supported"] for n in valid["nodes"]), valid
        assert all(e["clear"] for e in valid["edges"]), valid
        assert cmd("ui.snapshot")["map_rectangles"] == cmd("world.snapshot")["colliders"]
        if not ai_only and not e2_only:
            route_names = ["W2/room", "W2/stair_approach", "W2/stair_bottom", "W2/stair_top",
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

        if not e2_only:
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
            lower = nodes["W2/room"]
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
            # The authored bedroom is supported and hidden until the soldier
            # reaches this floor. The former corner is now blocked by furniture.
            target = nodes["W2/bedroom"]
            cmd("movement.reset", dict(x=target["x"], y=target["y"]+.01, z=target["z"], yaw=0))
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

        if not w2_only:
            # A continuous walk crosses the street, visits both E2 apartments, then
            # returns to W2's bedroom. Only the initial placement uses a reset.
            east_route=["W2/walk","W2/street","E2/street","E2/walk","E2/room",
                        "E2/stair_approach","E2/stair_bottom","E2/stair_top",
                        "E2/upper_hall","E2/upper_room","E2/bedroom","E2/upper_room",
                        "E2/upper_hall","E2/floor2/stair_approach","E2/floor2/stair_bottom",
                        "E2/floor2/stair_top","E2/floor2/upper_hall","E2/floor2/upper_room","E2/floor2/bedroom"]
            cmd("ai.configure", {"enabled": False})
            if not ai_only:
                cmd("movement.reset", dict(x=-9.5,y=.15,z=0,yaw=0))
                for name in east_route:
                    walk_to(nodes[name])
                    print("PASS player reached",name,flush=True)
                capture("e2_top_player")
                for name in reversed(east_route[:-1]):
                    walk_to(nodes[name])
                for name in ("W2/room","W2/stair_approach","W2/stair_bottom","W2/stair_top",
                             "W2/upper_hall","W2/upper_room","W2/bedroom"):
                    walk_to(nodes[name])
                print("PASS continuous W2-to-E2-all-floors-and-back traversal",flush=True)
                for level,prefix in ((1,"E2/upper"),(2,"E2/floor2")):
                    y=.145+level*3.2
                    hit=cmd("world.raycast",{"from":dict(x=10,y=y+1,z=-3),"to":dict(x=10,y=y-1,z=-3)})
                    assert hit["id"]==prefix+"/floor/west" and abs(hit["y"]-y)<.001,hit
                cmd("movement.reset",dict(x=15.7,y=6.55,z=-6,yaw=0))
                guard=drive([dict(ticks=120,move_x=1),dict(ticks=12)])
                assert guard["x"]<16.6 and guard["y"]>6.5,guard
                print("PASS E2 separate floor slabs and top-flight side guard",flush=True)

            # Keep the player hidden above W2 while an ordinary patrol crosses the
            # street and negotiates both E2 stair flights in each direction.
            cmd("movement.reset",dict(x=-10,y=3.35,z=.2,yaw=0))
            cmd("ai.reset",{"position":nodes["W2/room"],"yaw":0})
            game.wait_frames(4)
            target=nodes["E2/floor2/bedroom"]
            route=cmd("ai.route",{"target":target})["points"]
            assert route and any(.4<p["y"]<3.2 for p in route) and any(3.6<p["y"]<6.3 for p in route),route
            cmd("ai.patrol",{"points":[target]})
            cmd("ai.configure",{"enabled":True})
            def arrived(point):
                e=soldier()
                assert not e["recovery_failed"],e
                return math.dist([e[k] for k in ("x","y","z")],[point[k] for k in ("x","y","z")])<.5
            engine.wait_until(lambda:arrived(target),timeout=110,message="Enemy did not cross street and climb E2")
            print("PASS enemy traverses W2 to E2 second-floor bedroom",soldier(),flush=True)
            target=nodes["W2/room"]
            cmd("ai.patrol",{"points":[target]})
            engine.wait_until(lambda:arrived(target),timeout=110,message="Enemy did not descend E2 and return to W2")
            print("PASS enemy descends both E2 flights and returns to W2",flush=True)
            cmd("ai.configure",{"enabled":False})
            for name in ("e2_shop","e2_stairs","e2_upstairs","e2_top"):
                cmd("world.view",{"name":name})
                capture(name)
                assert cmd("audio.snapshot")["indoor"],name
                assert cmd("renderer.snapshot")["local_light_count"]==4
        print("WORLD", cmd("world.snapshot"), flush=True)
    except Exception:
        print("FAILED STATE", cmd("ai.snapshot"), cmd("ui.snapshot"), flush=True)
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
    scope=parser.add_mutually_exclusive_group()
    scope.add_argument("--e2-only", action="store_true", help="Run just the cross-building/E2 checks")
    scope.add_argument("--w2-only", action="store_true", help="Run just the original W2 checks")
    args=parser.parse_args()
    main(args.ai_only,args.e2_only,args.w2_only)
