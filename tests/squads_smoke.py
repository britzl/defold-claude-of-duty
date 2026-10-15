"""Six-soldier native encounter: cover, shared alerts, flank, deaths and profiling.
Run: PYTHONPATH=automation-bridge-python python3 tests/squads_smoke.py
"""
from dataclasses import asdict
import json
from pathlib import Path
import shutil
import time
from automation_bridge import editor, engine


def main():
    root = Path(__file__).resolve().parents[1]
    output = root / "build" / "squad-validation"
    output.mkdir(parents=True, exist_ok=True)
    project = editor.open_project(root, start_if_needed=False)
    game = project.build_and_run(timeout=180)

    def cmd(name, data=None):
        return game.command(name, data or {})["result"]

    def resume():
        if cmd("ui.snapshot")["paused"]:
            cmd("ui.focus", {"focused": True})
            cmd("ui.pause", {"paused": False})

    def snapshot():
        resume()
        return cmd("ai.snapshot")

    def reset(x, z):
        cmd("ai.configure", {"enabled": False, "damage_scale": 0})
        cmd("ai.reset")
        cmd("movement.reset", {"x": x, "y": .01, "z": z, "yaw": 0})
        game.wait_frames(4)
        cmd("ai.configure", {"enabled": True})
        # Current patrol spawns no longer see this fixture's player position.
        # A real player hit supplies the same observed target to each squad.
        for actor in ("enemy_1", "enemy_4"):
            cmd("gameplay.damage", {"target": actor, "amount": 1, "source": "player"})

    def capture(name):
        shot = game.screenshot(resolution_multiplier=.75)
        shutil.copyfile(shot.path, output / (name+".png"))

    report = {}
    try:
        engine.wait_until(lambda: game.state("world").value["ready"], timeout=25)
        engine.wait_until(lambda: len(snapshot()["actors"]) == 6, timeout=5)
        s = snapshot()
        assert len(s["squads"]) == 2 and all(len(q["members"]) == 3 for q in s["squads"].values()), s
        assert s["render"]["actors"] == 6 and s["render"]["objects"] == 54, s
        assert s["render"]["active_hitboxes"] == 42 and s["render"]["buffers"] == 1, s
        print("PASS native six-actor resources", s["render"], flush=True)

        # The west side of the street barrier protects from a player to its east.
        reset(4, -2.5)
        seen_cover = {}
        started = time.monotonic()
        def took_cover():
            s = snapshot()
            for e in s["actors"]:
                assert not e["recovery_failed"], e
                if e.get("cover"):
                    seen_cover[e["id"]] = e
                    if e["state"] == "fire" and e["shots"] > 0:
                        report["cover"] = s
                        return True
            if time.monotonic()-started > 8:
                print("COVER", [{k:e.get(k) for k in ("id","state","cover","x","z","shots")} for e in s["actors"]], flush=True)
            return False
        engine.wait_until(took_cover, timeout=20, interval=.25)
        assert seen_cover
        capture("cover")
        print("PASS native exclusive cover acquisition and fire from the protected position", list(seen_cover), flush=True)

        reset(0, 5)
        history = []
        last_print = [0]
        def completed_flank():
            s = snapshot()
            for e in s["actors"]:
                assert not e["recovery_failed"], e
                assert e["stuck"] < 1.6, e
            history.append(s)
            if time.monotonic()-last_print[0] > 6:
                last_print[0] = time.monotonic()
                print("COMBAT", [{k:e.get(k) for k in ("id","state","x","z","shots","flank_index","flanks_completed")} for e in s["actors"]], flush=True)
            return any(e["flanks_completed"] > 0 for e in s["actors"])
        engine.wait_until(completed_flank, timeout=65, interval=.25)
        report["flank"] = snapshot()
        assert any(e.get("flank") and e["x"] < -23 for s in history for e in s["actors"]), "No rear-lane traversal"
        assert sum(e["shots"] for e in report["flank"]["actors"]) > 12
        assert all(e["travel"] > .5 for e in report["flank"]["actors"])
        assert cmd("gameplay.snapshot")["health"] == 100
        capture("squads")
        print("PASS live engagement plus complete rear flank, all six actors move without failed recovery", flush=True)

        # Pause freezes the full encounter including reports and claims.
        cmd("ui.pause", {"paused": True})
        before = cmd("ai.snapshot")
        game.wait_frames(20)
        after = cmd("ai.snapshot")
        assert before["actors"] == after["actors"] and before["cover_claims"] == after["cover_claims"]
        cmd("ui.pause", {"paused": False})
        resume()
        profile = game.profiler.capture(frames=360, warmup_frames=10, timeout=20)
        report["profile"] = {"scopes": [asdict(s) for s in profile.scopes()],
                             "counters": [asdict(c) for c in profile.counters()]}
        report["costs"] = snapshot()
        print("PROFILE", {k:report["costs"][k] for k in ("mean_tick_ms", "peak_tick_ms")}, flush=True)
        print("DRAWS", [(c.name,c.values.avg,c.values.max) for c in profile.counters() if "draw" in c.name.lower()], flush=True)

        cmd("ai.configure", {"enabled": False})
        for e in snapshot()["actors"]:
            cmd("gameplay.damage", {"target": e["id"], "amount": 999, "source": "player"})
        engine.wait_until(lambda: all(e["death"] == 1 for e in snapshot()["actors"]), timeout=5)
        s = snapshot()
        assert s["render"]["active_hitboxes"] == 0 and not s["cover_claims"] and not s["flank_claims"], s
        assert len(cmd("ai.volumes")) == 0
        print("PASS six independent deaths disable all hit volumes and release claims", flush=True)
        for _ in range(8):
            cmd("ai.reset")
            game.wait_frames(3)
            s = snapshot()
            assert len(s["actors"]) == 6 and all(e["health"] == 100 for e in s["actors"])
            assert s["render"]["objects"] == 54 and s["render"]["active_hitboxes"] == 42 and s["render"]["buffers"] == 1
            assert len(cmd("ai.volumes")) == 42 and s["live"] == 0 and s["fired"] == 0
        cmd("gameplay.restart")
        game.wait_frames(5)
        s = snapshot()
        assert len(s["actors"]) == 6 and s["damage_scale"] == 1 and s["enabled"]
        assert cmd("gameplay.snapshot")["health"] == 100
        report["restart"] = s
        (output / "native.json").write_text(json.dumps(report, indent=2)+"\n")
        print("PASS eight full replacements and normal encounter restart without resource growth", flush=True)
    except Exception:
        print("FAILED STATE", cmd("ai.snapshot"), cmd("gameplay.snapshot"), flush=True)
        raise
    finally:
        game.close_engine()
        game.close()
    errors = [line for line in project.console.read().lines if "ERROR:" in line]
    assert not errors, "\n".join(errors)
    print("PASS clean shutdown without runtime errors", flush=True)


if __name__ == "__main__":
    main()
