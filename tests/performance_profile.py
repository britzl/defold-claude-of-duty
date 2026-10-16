"""Native Remotery comparison and exact rendering regression captures.

PYTHONPATH=automation-bridge-python:tests python3 tests/performance_profile.py \
    --output captures/performance/before
Repeat with --output captures/performance/after --compare captures/performance/before.
Use --visuals-only for a fresh-launch image control. Comparisons require exact
RGB equality unless --noise-control names a measured unchanged-code repeat;
then pixel count, peak error and mean error must all fit that control per view.
Requires Pillow and the open Defold editor. Owns and closes the engine it builds.
"""
import argparse
from dataclasses import asdict
from datetime import datetime, timezone
import gzip
import json
from pathlib import Path
import shutil
from PIL import Image, ImageChops, ImageStat
from automation_bridge import editor, engine
from render_baseline import source_fingerprint

ROOT = Path(__file__).resolve().parents[1]


def image_difference(reference, candidate):
    with Image.open(reference) as a, Image.open(candidate) as b:
        assert a.size == b.size == (1280,720)
        diff = ImageChops.difference(a.convert("RGB"), b.convert("RGB"))
        channels = diff.split()
        any_channel = ImageChops.lighter(ImageChops.lighter(channels[0],channels[1]),channels[2])
        return {"different_pixels": a.width*a.height-any_channel.histogram()[0],
            "max_channel_difference": max(high for low,high in diff.getextrema()),
            "mean_absolute_difference": sum(ImageStat.Stat(diff).sum)/(a.width*a.height*3),
            "exact_rgb_match": diff.getbbox() is None}


def within_control(difference, control):
    return all(difference[key] <= control[key] for key in
               ("different_pixels", "max_channel_difference", "mean_absolute_difference"))


def summarize(capture):
    frames = [f for f in capture.frames if f.thread_name == "Main"]
    assert frames and all(not f.partial and f.root.name == "Step" for f in frames)
    durations = sorted(f.root.duration_us / 1000 for f in frames)
    return {"samples": len(frames), "mean_ms": sum(durations) / len(frames),
        "p95_ms": durations[int(.95 * (len(frames) - 1))],
        "p99_ms": durations[int(.99 * (len(frames) - 1))], "max_ms": max(durations),
        "over_budget_pct": 100 * sum(t > 1000 / 60 for t in durations) / len(frames),
        "scopes": [dict(asdict(s), ms_per_frame=s.total.total_us / len(frames) / 1000,
                        self_ms_per_frame=s.self.total_us / len(frames) / 1000)
                   for s in capture.scopes(thread="Main")],
        "counters": [asdict(c) for c in capture.counters()]}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--compare", type=Path)
    parser.add_argument("--frames", type=int, default=600)
    parser.add_argument("--no-visuals", action="store_true")
    parser.add_argument("--visuals-only", action="store_true")
    parser.add_argument("--noise-control", type=Path)
    args = parser.parse_args()
    if args.noise_control and not args.compare: parser.error("--noise-control requires --compare")
    if args.visuals_only and args.no_visuals: parser.error("--visuals-only conflicts with --no-visuals")
    output = args.output.resolve(); output.mkdir(parents=True, exist_ok=False)
    reference = json.loads((args.compare / "report.json").read_text()) if args.compare else None
    control = json.loads((args.noise_control / "report.json").read_text()) if args.noise_control else None
    report = {"created_utc": datetime.now(timezone.utc).isoformat(),
        "source_sha256": source_fingerprint(), "profiles": {}, "images": {},
        "image_reference": str(args.compare.resolve()) if args.compare else None,
        "noise_control": str(args.noise_control.resolve()) if args.noise_control else None,
        "method": "Native debug Metal, Main/Step elapsed times; not GPU timestamps. AI damage disabled."}
    def save_report(): (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    project = editor.open_project(ROOT, start_if_needed=False)
    game = project.build_and_run(timeout=180, focus=True)
    def cmd(name, data=None): return game.command(name, data or {})["result"]
    def state(): return {key: cmd(key + ".snapshot") for key in ("gameplay", "ai", "renderer", "weapons")}
    def settle(count=60): game.wait_frames(count, timeout=30)
    def size(w, h):
        game.resize(w, h); settle(20)
        actual = cmd("renderer.snapshot")
        game.resize(round(w*w/actual["width"]), round(h*h/actual["height"]))
        engine.wait_until(lambda: (cmd("renderer.snapshot")["width"], cmd("renderer.snapshot")["height"]) == (w,h), timeout=15)
        settle()
    def live():
        cmd("gameplay.restart"); cmd("ui.focus", {"focused": True}); cmd("ui.pause", {"paused": False})
        cmd("ai.configure", {"damage_scale": 0}); settle(90)
        assert not cmd("gameplay.snapshot")["paused"]
    def record(name, drive=None, segments=None, frozen=False):
        before = state()
        if drive:
            recording = game.profiler.start_recording(thread="Main", warmup_frames=5, max_frames=4000)
            try:
                cmd(drive + ".drive", {"segments": segments})
                engine.wait_until(lambda: cmd(drive + ".result")["complete"], timeout=45, interval=.25)
            finally: capture = recording.stop()
        else:
            capture = game.profiler.capture(frames=args.frames, warmup_frames=30, thread="Main", timeout=60)
        after = state()
        if not frozen:
            assert not before["gameplay"]["paused"] and not after["gameplay"]["paused"], "Paused profile: " + name
            assert after["gameplay"]["tick"] > before["gameplay"]["tick"]
            assert after["gameplay"]["alive"] and len(after["ai"]["actors"]) == 6
            assert not after["gameplay"]["recovery_failed"]
            assert not any(a["recovery_failed"] for a in after["ai"]["actors"])
        result = dict(summarize(capture), before=before, after=after)
        if drive: result["drive"] = cmd(drive + ".result")
        report["profiles"][name] = result
        with gzip.open(output / (name + "-raw.json.gz"), "wt") as stream: json.dump(asdict(capture), stream)
        save_report()
        print("PROFILE", name, {k: result[k] for k in ("samples", "mean_ms", "p95_ms", "max_ms")}, flush=True)
        print("SCOPES", [(s["name"], round(s["ms_per_frame"], 4)) for s in result["scopes"]
                         if s["name"] in ("fixed.ai", "ai.movement", "ai.fire", "ai.navigation", "fixed.weapons")], flush=True)
    try:
        engine.wait_until(lambda: cmd("world.snapshot")["ready"] and cmd("renderer.snapshot")["ready"], timeout=90)
        report["world"] = cmd("world.snapshot"); report["health"] = game.health()
        if not args.visuals_only:
            size(1920,1280)
            for suffix in ("a", "b"):
                live(); record("live-default-" + suffix)
            size(1280,720)
            for suffix in ("a", "b"):
                live(); record("live-spawn-720p-" + suffix)
                live(); record("forward-sprint-720p-" + suffix, "movement",
                    [{"ticks": 720, "move_z": -1, "sprint": True}, {"ticks": 240}])
            live(); record("live-fire-720p", "weapons", [
                {"ticks": 360, "aim": True, "fire": True}, {"ticks": 360, "reload": True},
                {"ticks": 360, "aim": True, "fire": True}, {"ticks": 360, "reload": True}])
            for shot in ("street", "interior", "courtyard", "detail"):
                cmd("capture.shot", {"name": shot}); settle()
                record("frozen-" + shot + "-720p", frozen=True)
            report["profiles_complete"] = True
        else:
            size(1280,720)
        differences = []
        if not args.no_visuals:
            for shot in ("street", "interior", "courtyard", "detail", "sunset", "night", "sky_daylight",
                         "sky_sunset", "sky_night", "window_shafts", "moon", "rifle_hip", "rifle_ads", "combat_effects"):
                cmd("capture.shot", {"name": shot}); settle()
                filename = shot + ".png"
                shutil.copyfile(game.screenshot(after_frames=1).path, output / filename)
                receipt = {"file": filename, "capture": cmd("capture.snapshot"), "renderer": cmd("renderer.snapshot")}
                if reference:
                    receipt.update(image_difference(args.compare / filename, output / filename))
                    if control:
                        receipt["within_control_variance"] = within_control(receipt, control["images"][shot])
                    if not receipt["exact_rgb_match"] and not receipt.get("within_control_variance"):
                        differences.append(shot)
                report["images"][shot] = receipt; save_report()
                print("IMAGE", shot, receipt.get("exact_rgb_match", "baseline"), flush=True)
        cmd("capture.end")
        assert not differences, "Pixel differences (all captures saved): " + ", ".join(differences)
        report["complete"] = True
    finally:
        game.close_engine(); game.close()
        lines = project.console.read().lines
        (output / "console.txt").write_text("\n".join(lines) + "\n")
        report["console_issues"] = [line for line in lines if "ERROR:" in line or "WARNING:" in line]
        save_report()
    assert not report["console_issues"], report["console_issues"]
    print("PASS profile and rendering capture", output, flush=True)


if __name__ == "__main__": main()
