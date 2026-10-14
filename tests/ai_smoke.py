"""Native generated skinning, Bullet hit volumes and one-enemy combat checks.
Run: PYTHONPATH=automation-bridge-python python3 tests/ai_smoke.py
"""
import math
from pathlib import Path
from automation_bridge import editor, engine


def main():
    project = editor.open_project(Path(__file__).resolve().parents[1], start_if_needed=False)
    game = project.build_and_run(timeout=180)

    def command(name, data=None):
        return game.command(name, data or {})["result"]

    def state():
        return command("ai.snapshot")

    def soldier():
        return state()["actors"][0]

    def player(x=0, z=2):
        command("movement.reset", dict(x=x, y=.01, z=z, yaw=0))
        game.wait_frames(4)

    def reset_enemy(x=0, z=-5, enabled=False):
        command("ai.configure", dict(enabled=enabled))
        command("ai.reset", dict(position=dict(x=x, y=.004, z=z), yaw=math.pi))
        game.wait_frames(4)

    def drive(segments, kind="weapons"):
        command(kind+".drive", dict(segments=segments))
        engine.wait_until(lambda: command(kind+".result")["complete"], timeout=25)
        return command(kind+".result")["result"]

    def capture(name):
        print("SCREENSHOT", name, game.screenshot(resolution_multiplier=.75).path, flush=True)

    def shot():
        return drive([dict(ticks=100, aim=True), dict(ticks=1, fire=True, aim=True), dict(ticks=35, aim=True)])

    try:
        engine.wait_until(lambda: game.state("world").value["ready"], timeout=25)
        engine.wait_until(lambda: len(state()["actors"]) == 6, timeout=5)
        before = soldier()["travel"]
        game.wait_frames(50)
        assert soldier()["travel"] > before + .25
        render = state()["render"]
        assert render["vertices"] == 7140 and render["buffers"] == 1 and render["active_hitboxes"] == 42, render
        assert render["palette_uploads"] > 10 and render["palette_bytes"] == 1600, render
        print("PASS generated mesh, 25-bone palette uploads and native patrol", render, flush=True)

        player(z=-1)
        reset_enemy()
        capture("soldier_idle")
        before = soldier()["health"]
        shot()
        head_damage = before - soldier()["health"]
        assert 65 < head_damage < 68, (head_damage, state())
        print("PASS native head volume and doubled damage", head_damage, flush=True)

        player()
        reset_enemy()
        pitch = math.atan2(1.30 - 1.664, 7)
        drive([dict(ticks=1, look_y=pitch/.0022)], "movement")
        shot()
        body_damage = 100 - soldier()["health"]
        assert 32 < body_damage < 34, (body_damage, state())
        assert head_damage > body_damage*1.95
        print("PASS rotated skeleton body volume and single damage owner", body_damage, flush=True)

        command("gameplay.damage", dict(target="enemy_1", amount=1000, source="player"))
        engine.wait_until(lambda: soldier()["death"] >= 1, timeout=4)
        assert soldier()["state"] == "dead" and state()["render"]["active_hitboxes"] == 0
        capture("soldier_death")
        print("PASS death collapse and immediate hit-volume disable", flush=True)

        command("gameplay.restart")
        player(z=0)
        reset_enemy(z=-13, enabled=True)
        engine.wait_until(lambda: soldier()["state"] == "pursuit", timeout=5)
        capture("soldier_walk")
        engine.wait_until(lambda: soldier()["shots"] >= 2, timeout=8)
        engine.wait_until(lambda: command("gameplay.snapshot")["health"] < 100, timeout=4)
        assert soldier()["travel"] > 2
        capture("soldier_aim")
        print("PASS detection, pursuit, animated muzzle fire and real Bullet player damage", soldier(), flush=True)

        # A room wall removes sight immediately; already-fired rounds may finish.
        player(x=-10, z=-3)
        game.wait_frames(5)
        shots = soldier()["shots"]
        drive([dict(ticks=180)])
        assert soldier()["shots"] == shots and not soldier()["visible"]
        print("PASS room occlusion stops firing", flush=True)

        # Patrol into W2 while the player is on the distant firing-range floor.
        command("ai.configure", dict(enabled=False))
        reset_enemy(z=-8)
        route = command("ai.route", dict(target=dict(x=-9.5, y=.145, z=0)))["points"]
        assert len(route) >= 2, route
        assert any(abs(p["z"]) < .3 for p in route[:-1]), route
        command("weapons.range")
        player(x=-5, z=40)
        command("ai.patrol", dict(points=[dict(x=-9.5, y=.145, z=0)]))
        command("ai.configure", dict(enabled=True))
        engine.wait_until(lambda: soldier()["x"] < -7, timeout=18)
        assert soldier()["x"] < -6.5 and soldier()["y"] > .10, (route, soldier())
        assert not soldier()["recovery_failed"]
        command("world.view", dict(name="room"))
        game.wait_frames(3)
        capture("soldier_room")
        print("PASS native supported doorway route and capsule room entry", soldier(), flush=True)

        # Replacement must release GOs/hit registries and reuse the shared buffer.
        for _ in range(8):
            reset_enemy()
        game.wait_frames(3)
        render = state()["render"]
        assert render["objects"] == 9 and render["buffers"] == 1 and render["active_hitboxes"] == 7, render
        assert len(command("ai.volumes")) == 7
        command("gameplay.damage", dict(target="player", amount=1000))
        engine.wait_until(lambda: not command("gameplay.snapshot")["alive"], timeout=3)
        game.key("9", wait="released")
        game.wait_frames(5)
        assert command("gameplay.snapshot")["health"] == 100 and soldier()["health"] == 100
        assert command("weapons.snapshot")["ammo"] == 31 and state()["enabled"]
        print("PASS repeated replacement, bounded resources and key-9 encounter restart", render, flush=True)
    finally:
        game.close_engine()
        game.close()
    errors = [line for line in project.console.read().lines if "ERROR:" in line]
    assert not errors, "\n".join(errors)
    print("PASS clean soldier-test shutdown; no runtime errors", flush=True)


if __name__ == "__main__":
    main()
