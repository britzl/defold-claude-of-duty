"""Capture versioned rendering baselines. Owns the Defold engine it builds.

PYTHONPATH=automation-bridge-python python3 tests/render_baseline.py --motion
Requires Pillow; ffmpeg optionally encodes the deterministic PNG sequence.
"""
import argparse
from datetime import datetime, timezone
from dataclasses import asdict
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

from PIL import Image, ImageChops, ImageDraw
from automation_bridge import editor, engine

ROOT = Path(__file__).resolve().parents[1]


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def source_fingerprint():
    digest = hashlib.sha256()
    for folder in ("game", "main", "render", "world", "weapons", "soldiers"):
        for path in sorted((ROOT / folder).rglob("*")):
            if path.is_file():
                digest.update(str(path.relative_to(ROOT)).encode())
                digest.update(path.read_bytes())
    digest.update((ROOT / "game.project").read_bytes())
    return digest.hexdigest()


def capture_baseline(output, motion, profile):
    output.mkdir(parents=True, exist_ok=False)
    project = editor.open_project(ROOT, start_if_needed=False)
    game = project.build_and_run(timeout=180)
    report = {"engine": "defold", "revision": git("rev-parse", "HEAD"),
              "source_sha256": source_fingerprint(),
              "working_tree": git("status", "--short"), "shots": {},
              "created_utc": datetime.now(timezone.utc).isoformat(),
              "references": {"threejs": "Capture separately with tools/capture_reference.mjs.",
                             "kaigen": "Pending: local engine checkout is unavailable."}}

    def cmd(name, data=None):
        return game.command(name, data or {})["result"]

    def save(name):
        path = output / name
        receipt = game.screenshot(after_frames=3)
        shutil.copyfile(receipt.path, path)
        with Image.open(path) as img:
            assert img.size == (catalog["width"], catalog["height"]), img.size
        return path

    try:
        engine.wait_until(lambda: cmd("world.snapshot")["ready"], timeout=45)
        engine.wait_until(lambda: cmd("renderer.snapshot")["ready"], timeout=10)
        catalog = cmd("capture.catalog")
        report["catalog"] = catalog
        report["world"] = cmd("world.snapshot")
        report["engine_health"] = game.health()
        game.resize(catalog["width"], catalog["height"])
        game.wait_frames(40)
        size = cmd("renderer.snapshot")
        # Resize logical window dimensions to obtain the requested real pixels on HiDPI.
        game.resize(round(catalog["width"]**2 / size["width"]),
                    round(catalog["height"]**2 / size["height"]))
        engine.wait_until(lambda: (cmd("renderer.snapshot")["width"], cmd("renderer.snapshot")["height"]) ==
                          (catalog["width"], catalog["height"]), timeout=10)
        cmd("renderer.configure", {"exposure": .75, "fog": False})
        engine.wait_until(lambda: cmd("renderer.snapshot")["settings"]["exposure"] == .75, timeout=5)
        original = cmd("renderer.snapshot")["settings"]
        for shot in catalog["shots"]:
            name = shot["id"]
            if shot.get("unsupported"):
                report["shots"][name] = {"status": "unsupported", "reason": shot["unsupported"]}
                continue
            snapshot = cmd("capture.shot", {"name": name})
            game.wait_frames(catalog["settle_frames"])
            path = save(name + ".png")
            # Re-select after another camera to prove wall-clock/order independence.
            cmd("capture.shot", {"name": "interior" if name == "street" else "street"})
            game.wait_frames(3)
            cmd("capture.shot", {"name": name})
            game.wait_frames(catalog["settle_frames"])
            repeat = save(name + "-repeat.png")
            with Image.open(path) as a, Image.open(repeat) as b:
                assert ImageChops.difference(a.convert("RGB"), b.convert("RGB")).getbbox() is None, name
            repeat.unlink()
            assert cmd("capture.snapshot")["simulation_tick"] == snapshot["simulation_tick"]
            report["shots"][name] = {"status": "captured", "image": path.name,
                                    "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                                    "repeat_identical": True, "capture": snapshot,
                                    "renderer": cmd("renderer.snapshot")}
            if profile:
                costs = game.profiler.capture(frames=60, warmup_frames=10, timeout=15)
                report["shots"][name]["profile"] = {
                    "scope": "Frozen scene: CPU scopes and submitted counters, not sustained combat or GPU timing.",
                    "scopes": [asdict(scope) for scope in costs.scopes()[:12]],
                    "counters": [asdict(counter) for counter in costs.counters()]}
            print("CAPTURE", name, "repeat pixels identical", flush=True)
        if motion:
            report["motions"]={}
            for shot_name in ("laboratory", "material_grazing", "weathering_facade", "shadow_distance", "shadow_cutout"):
                directory=shot_name+"-sweep"
                sequence=output/directory;sequence.mkdir()
                cmd("capture.shot", {"name": shot_name})
                samples=[]
                for frame in range(catalog["sweep_frames"]):
                    samples.append(cmd("capture.frame", {"frame": frame}))
                    game.wait_frames(catalog["settle_frames"])
                    save(f"{directory}/{frame:04d}.png")
                    if frame%30==0:
                        print("SWEEP",shot_name,frame,"/",catalog["sweep_frames"]-1,flush=True)
                record={"fps":catalog["sweep_fps"],"samples":samples,"sequence":directory+"/%04d.png",
                    "timing":"frame-addressed; not a real-time performance recording"}
                if shutil.which("ffmpeg"):
                    subprocess.run(["ffmpeg","-v","error","-framerate",str(catalog["sweep_fps"]),
                        "-i",str(sequence/"%04d.png"),"-c:v","libx264","-crf","16","-pix_fmt","yuv420p",
                        str(output/(directory+".mp4"))],check=True)
                    record["video"]=directory+".mp4"
                report["motions"][shot_name]=record
            report["motion"]=report["motions"]["laboratory"]
        assert not cmd("capture.end")["active"]
        game.wait_frames(35)
        assert cmd("renderer.snapshot")["settings"] == original
        # Re-enter/release the fixture to exercise ownership and deferred deletion.
        cmd("capture.shot", {"name": "laboratory"})
        game.wait_frames(5)
        assert cmd("capture.snapshot")["lab_meshes"] == 28
        cmd("capture.end")
        report["cleanup"] = "Settings restored; laboratory can be recreated and released."
    finally:
        (output / "manifest.json").write_text(json.dumps(report, indent=2, default=str) + "\n")
        game.close_engine()
        game.close()
    errors = [line for line in project.console.read().lines if "ERROR:" in line]
    assert not errors, "\n".join(errors)
    captured = [(name, shot) for name, shot in report["shots"].items() if shot["status"] == "captured"]
    sheet = Image.new("RGB", (960, ((len(captured)+1)//2)*300), "#20252b")
    draw = ImageDraw.Draw(sheet)
    for i, (name, shot) in enumerate(captured):
        with Image.open(output / shot["image"]) as img:
            img.thumbnail((480, 270))
            x, y = (i % 2)*480, (i // 2)*300
            sheet.paste(img, (x, y))
            draw.text((x+12, y+278), name, fill="white")
    sheet.save(output / "contact-sheet.jpg")
    print("PASS baseline, exact repeated captures, frozen simulation and cleanup:", output, flush=True)
    return report


def repeated_launches(output, motion, profile, launches):
    assert launches >= 1
    if launches == 1:
        return capture_baseline(output, motion, profile)
    output.mkdir(parents=True, exist_ok=False)
    reports = []
    for launch in range(launches):
        folder = output / f"launch-{launch+1}"
        report = capture_baseline(folder, motion and launch == 0, profile and launch == 0)
        if reports:
            first = reports[0]
            assert first["source_sha256"] == report["source_sha256"], "Source changed between launches"
            assert first["catalog"] == report["catalog"]
            for name, shot in first["shots"].items():
                if shot["status"] != "captured":
                    continue
                other = report["shots"][name]
                assert shot["renderer"]["settings"] == other["renderer"]["settings"]
                assert shot["renderer"].get("pipeline") == other["renderer"].get("pipeline"), "Renderer backend changed"
                with Image.open(output / "launch-1" / shot["image"]) as a, Image.open(folder / other["image"]) as b:
                    assert ImageChops.difference(a.convert("RGB"), b.convert("RGB")).getbbox() is None, (launch+1, name)
        reports.append(report)
    (output / "repeatability.json").write_text(json.dumps({"launches": launches,
        "source_sha256": reports[0]["source_sha256"], "all_captured_pixels_identical": True}, indent=2)+"\n")
    print("PASS exact pixels across", launches, "independent engine launches", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "captures" / "rendering" /
                        ("defold-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")))
    parser.add_argument("--motion", action="store_true")
    parser.add_argument("--profile", action="store_true")
    parser.add_argument("--launches", type=int, default=1, help="Gate every captured RGB pixel across fresh engine launches")
    args = parser.parse_args()
    repeated_launches(args.output.resolve(), args.motion, args.profile, args.launches)
