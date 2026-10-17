"""Generated WAV playback, actual stereo mixer output and gameplay event wiring.
Run: PYTHONPATH=automation-bridge-python python3 tests/audio_smoke.py
"""
import json
from pathlib import Path
from automation_bridge import editor, engine


def main():
    project = editor.open_project(Path(__file__).resolve().parents[1], start_if_needed=False)
    game = project.build_and_run(timeout=180, focus=False)
    focus_restores = 0

    def command(name, data=None):
        nonlocal focus_restores
        # Desktop focus changes legitimately pause gameplay and stop voices.
        # This integration test runs an active encounter, even in background.
        if not name.startswith("ui."):
            ui = game.command("ui.snapshot", {})["result"]
            if ui["paused"] or not ui["focused"]:
                game.command("ui.focus", dict(focused=True))
                game.command("ui.pause", dict(paused=False))
                focus_restores += 1
        return game.command(name, data or {})["result"]

    def state():
        return command("audio.snapshot")

    def settle():
        engine.wait_until(lambda: state()["active"] == 2, timeout=5)
        game.wait_frames(12)

    def drive(segments, kind="weapons"):
        command(kind + ".drive", dict(segments=segments))
        engine.wait_until(lambda: command(kind + ".result")["complete"], timeout=20)
        return command(kind + ".result")["result"]

    def preview(**data):
        for attempt in range(3):
            settle()
            played = state()["played"]
            restores = focus_restores
            command("audio.preview", data)
            # Return the snapshot that actually observed the mixer transient.
            def audible():
                snapshot = state()
                return snapshot if snapshot["played"] > played and max(snapshot["meter"].values()) > .0001 else None
            try:
                return engine.wait_until(audible, timeout=2, interval=.01)
            except engine.WaitTimeoutError:
                # Retry only a cue interrupted by a real focus/pause event.
                if focus_restores > restores and attempt < 2:
                    continue
                print("PREVIEW FAILURE", data, state(), command("gameplay.snapshot"), flush=True)
                raise

    try:
        engine.wait_until(lambda: game.state("world").value["ready"], timeout=25)
        command("ui.focus", dict(focused=True))
        command("ui.pause", dict(paused=False))
        command("ai.configure", dict(enabled=False))
        assert state()["ready"] and state()["loaded"] == 76
        assert state()["synthesis_backend"] == "native"
        assert state()["bytes"] == 1627520 and state()["voice_limit"] == 24
        engine.wait_until(lambda: max(state()["meter"].values()) > .0001, timeout=4)
        print("PASS runtime bank and audible ambience", state()["work_ms"], state()["peak_job_ms"], flush=True)
        command("audio.configure", dict(ambience=0))
        command("movement.reset", dict(x=0, y=.01, z=4, yaw=0))

        right = preview(kind="shot", weapon="rifle", position=dict(x=4, y=1.66, z=4))
        assert right["last"]["pan"] > .85 and not right["last"]["occluded"], right
        assert right["meter"]["right"] > right["meter"]["left"] * 1.5, right
        near_gain = next(v["gain"] for v in right["voices"] if v["slot"] <= 22)
        left = preview(kind="shot", weapon="rifle", position=dict(x=-4, y=1.66, z=4))
        assert left["last"]["pan"] < -.85, left
        assert left["meter"]["left"] > left["meter"]["right"] * 1.5, left
        far = preview(kind="shot", weapon="rifle", position=dict(x=0, y=1.66, z=45))
        far_gain = next(v["gain"] for v in far["voices"] if v["slot"] <= 22)
        assert far_gain < near_gain * .15, (near_gain, far_gain)
        print("PASS native stereo mixer channels and distance attenuation", flush=True)

        wall = preview(kind="shot", weapon="rifle", position=dict(x=-12, y=1.8, z=-6))
        assert wall["last"]["occluded"] and wall["last"]["key"].endswith("muffled"), wall
        command("world.view", dict(name="room"))
        room = preview(kind="shot", weapon="pistol")
        assert room["indoor"] and room["last"]["key"].endswith("room"), room
        print("PASS real Bullet occlusion and room variant", flush=True)

        command("movement.reset", dict(x=0, y=.01, z=4, yaw=0))
        for weapon in ("rifle", "smg", "pistol"):
            before = state()["by_kind"].get("shot", 0)
            drive([dict(ticks=150, **{"weapon_" + weapon: True}), dict(ticks=1, fire=True), dict(ticks=50)])
            assert state()["by_kind"].get("shot", 0) > before, (weapon, state())
        before = state()["by_kind"].get("reload", 0)
        drive([dict(ticks=1, reload=True), dict(ticks=300)])
        assert state()["by_kind"].get("reload", 0) >= before + 4, state()
        before = state()["by_kind"].get("step", 0)
        drive([dict(ticks=120, move_x=1), dict(ticks=120, move_x=-1)], "movement")
        assert state()["by_kind"].get("step", 0) > before, state()
        before = state()["by_kind"].get("hurt", 0)
        command("gameplay.damage", dict(target="player", amount=5))
        game.wait_frames(4)
        assert state()["by_kind"].get("hurt", 0) == before + 1
        print("PASS real three-weapon fire, reload beats, movement footsteps and damage", flush=True)

        for surface in ("concrete", "wood", "metal", "glass", "fabric", "water"):
            sound = preview(kind="impact", surface=surface)
            assert sound["last"]["key"] == "impact/" + surface
            assert max(sound["meter"].values()) > .0001, sound
        print("PASS surface bank playback produces mixer output", flush=True)

        command("audio.configure", dict(muted=True))
        engine.wait_until(lambda: state()["active"] == 0, timeout=3)
        # An idle device can retain its last meter buffer. The stop callbacks
        # prove mute completion; test zero gain with active loops separately.
        command("audio.configure", dict(muted=False, master=0, ambience=.6))
        engine.wait_until(lambda: state()["active"] == 2, timeout=3)
        engine.wait_until(lambda: max(state()["meter"].values()) < .000001, timeout=3)
        command("audio.configure", dict(master=.8))
        for _ in range(6):
            command("audio.preview", dict(kind="shot", weapon="rifle"))
            game.wait_frames(2)
            command("gameplay.restart")
            command("ai.configure", dict(enabled=False))
            settle()
            assert state()["loaded"] == 76 and state()["bytes"] == 1627520 and state()["active"] == 2
        assert state()["peak_voices"] <= 24 and state()["completed"] > 20, state()
        print("PASS mute silence, completion callbacks and six restarts without bank growth", flush=True)

        command("movement.reset", dict(x=0, y=.01, z=0, yaw=0))
        command("ai.reset", dict(position=dict(x=2, y=.004, z=-5), yaw=3.14159265))
        command("ai.configure", dict(enabled=True))
        before = state()["by_kind"].get("shot", 0)
        engine.wait_until(lambda: command("ai.snapshot")["actors"][0]["shots"] >= 2, timeout=10)
        assert state()["by_kind"].get("shot", 0) >= before + 2, state()
        print("PASS enemy physical-round fire is audible", flush=True)
        output = Path("build/audio-validation")
        output.mkdir(parents=True, exist_ok=True)
        (output / "native.json").write_text(json.dumps(state(), indent=2))
        errors = [line for line in project.console.read().lines if "ERROR:" in line or "WARNING:SOUND" in line]
        assert not errors, errors
    finally:
        game.close_engine()
        game.close()
    errors = [line for line in project.console.read().lines if "ERROR:" in line or "WARNING:SOUND" in line]
    assert not errors, errors
    print("PASS native shutdown without audio/resource errors", flush=True)


if __name__ == "__main__":
    main()
