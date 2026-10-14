"""Native market-loop traversal, patrol/pursuit, review views and profiler costs.
Run with PYTHONPATH=automation-bridge-python; owns the engine it builds.
"""
import argparse
from dataclasses import asdict
import json
import math
from pathlib import Path
import shutil
import time

from automation_bridge import editor, engine


def main(ai_only=False, views_only=False):
    root = Path(__file__).resolve().parents[1]
    output = root / "build" / "market-validation"
    output.mkdir(parents=True, exist_ok=True)
    project = editor.open_project(root, start_if_needed=False)
    game = project.build_and_run(timeout=180)

    def cmd(name, data=None):
        return game.command(name, data or {})["result"]

    def keep_running():
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
            p = cmd("gameplay.snapshot")
            dx, dz = point["x"]-p["x"], point["z"]-p["z"]
            distance = math.hypot(dx, dz)
            if distance < .14:
                drive([dict(ticks=12)])
                p = cmd("gameplay.snapshot")
                assert abs(p["y"]-point["y"]) < .08 and p["grounded"], (point, p)
                return
            speed = min(3, distance*3)
            drive([dict(ticks=24, move_x=dx/distance*speed/(4.57*.92),
                        move_z=dz/distance*speed/(4.57*(.8 if dz > 0 else 1)))])
        raise AssertionError(("Player stuck", point, cmd("gameplay.snapshot")))

    def soldier():
        keep_running()
        return cmd("ai.snapshot")["actors"][0]

    def wait_for_actor(point, timeout=45):
        progress = [0]

        def arrived():
            e = soldier()
            assert not e["recovery_failed"], e
            if time.monotonic()-progress[0] > 10:
                progress[0] = time.monotonic()
                print("AI", {k: e[k] for k in ("x", "y", "z", "state", "travel")}, flush=True)
            return math.dist([e[k] for k in ("x", "y", "z")], [point[k] for k in ("x", "y", "z")]) < .5

        engine.wait_until(arrived, timeout=timeout, message="Enemy stuck in market loop")

    try:
        engine.wait_until(lambda: game.state("world").value["ready"], timeout=25)
        engine.wait_until(lambda: len(cmd("ai.snapshot")["actors"]) == 1, timeout=5)
        cmd("ai.configure", {"enabled": False})
        world = cmd("world.snapshot")
        assert world["batches"] < 100 and world["mesh_bytes"] < 1024*1024, world
        assert world["colliders"] <= 256, world
        assert cmd("ui.snapshot")["map_rectangles"] == world["colliders"]
        valid = cmd("world.validate")
        assert valid["max_error"] < 1e-5 and all(n["supported"] for n in valid["nodes"]), valid
        assert all(e["clear"] for e in valid["edges"]), valid
        nodes = {n["id"]: n for n in cmd("world.navigation")["nodes"]}
        prefix = "west_loop/"
        flank = ["north_entry/street", "north_entry/walk", "north_entry", "courtyard",
                 "rear_north", "rear_mid", "rear_south", "alley", "south_entry",
                 "south_entry/walk", "south_entry/street"]

        if not ai_only and not views_only:
            cmd("movement.reset", dict(x=0, y=.01, z=7.5, yaw=0))
            circuit = [nodes[prefix+n] for n in flank]
            circuit += [nodes[n] for n in ("E2/street", "W2/street", prefix+"north_entry/street")]
            for point in circuit:
                walk_to(point)
                print("PASS player reached", point["id"], flush=True)
            # Reverse travel checks both raised and lowered kerb transitions.
            for point in reversed(circuit[:-1]):
                walk_to(point)
            print("PASS continuous market circuit in both directions, without jumps or resets", flush=True)

            # Cover and new dirt ground use the same installed geometry as metadata.
            for z, expected in ((8.9, "cover/courtyard"), (-10.9, "cover/alley")):
                hit = cmd("world.raycast", {"from": dict(x=-13.5, y=2, z=z),
                                            "to": dict(x=-13.5, y=0, z=z)})
                assert hit["id"] == expected and abs(hit["y"]-1.1) < .001, hit
            hit = cmd("world.raycast", {"from": dict(x=-23.5, y=1, z=0), "to": dict(x=-23.5, y=-1, z=0)})
            assert hit["surface"] == "dirt" and abs(hit["y"]) < .001, hit

        if not views_only:
            # Hide the player upstairs while an ordinary patrol follows the whole
            # circuit, through both mouths and the independent street return.
            cmd("movement.reset", dict(x=10, y=6.55, z=-9, yaw=0))
            cmd("ai.reset", {"position": nodes[prefix+"north_entry/street"], "yaw": 0})
            game.wait_frames(4)
            targets = ["north_entry", "rear_north", "rear_south", "south_entry", "south_entry/street", "north_entry/street"]
            for name in targets:
                point = nodes[prefix+name]
                route = cmd("ai.route", {"target": point})["points"]
                assert route, (name, soldier())
                cmd("ai.patrol", {"points": [point]})
                cmd("ai.configure", {"enabled": True})
                wait_for_actor(point)
                print("PASS enemy patrol reached", name, flush=True)
            assert soldier()["travel"] > 75, soldier()

            # Alert across W2's corner: the direct sightline is blocked, so the
            # soldier must route around the building before acquiring and firing.
            cmd("ai.configure", {"enabled": False})
            cmd("movement.reset", dict(x=-23.5, y=.01, z=-10, yaw=0))
            cmd("ai.reset", {"position": nodes[prefix+"courtyard"], "yaw": 0})
            game.wait_frames(4)
            hit = cmd("world.raycast", {"from": dict(x=-18, y=1.5, z=7.5),
                                        "to": dict(x=-23.5, y=1.5, z=-10)})
            assert hit["hit"] and hit["id"].startswith("W2/"), hit
            cmd("gameplay.damage", dict(target="enemy_1", amount=1, source="player"))
            cmd("ai.configure", {"enabled": True})
            engine.wait_until(lambda: soldier()["state"] == "pursuit", timeout=3)
            engine.wait_until(lambda: soldier()["x"] < -22 and soldier()["z"] < 4, timeout=15)
            engine.wait_until(lambda: soldier()["shots"] > 0, timeout=12)
            print("PASS alerted enemy rounds W2, enters the rear lane and fires after acquiring sight", soldier(), flush=True)
            cmd("ai.configure", {"enabled": False})

        # Captures and short idle-view profiles measure actual submitted draws
        # and CPU scopes. They are diagnostics, not a sustained combat benchmark.
        report = {"world": world, "views": {}}
        for name in ("street", "courtyard", "rear", "alley"):
            keep_running()
            cmd("world.view", {"name": name})
            game.wait_frames(8)
            shot = game.screenshot(resolution_multiplier=.75)
            shutil.copyfile(shot.path, output / (name+".png"))
            capture = game.profiler.capture(frames=90, warmup_frames=10, timeout=15)
            report["views"][name] = {
                "scopes": [asdict(s) for s in capture.scopes()[:12]],
                "counters": [asdict(c) for c in capture.counters()],
            }
            print("CAPTURE", name, "COUNTERS", [(c.name, c.values.avg, c.values.max) for c in capture.counters() if "draw" in c.name.lower()], flush=True)
        report["renderer"] = cmd("renderer.snapshot")
        (output / "costs.json").write_text(json.dumps(report, indent=2)+"\n")
        print("PASS market resource budgets and captures", world, flush=True)
    finally:
        game.close_engine()
        game.close()
    errors = [line for line in project.console.read().lines if "ERROR:" in line]
    assert not errors, "\n".join(errors)
    print("PASS clean shutdown without runtime errors", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--ai-only", action="store_true")
    parser.add_argument("--views-only", action="store_true")
    args = parser.parse_args()
    main(ai_only=args.ai_only, views_only=args.views_only)
