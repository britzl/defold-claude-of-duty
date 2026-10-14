"""Qualify the actual RGBA16F targets, samplers and AgX shader on native Metal.

PYTHONPATH=automation-bridge-python python3 tests/hdr_smoke.py
Owns/closes its engine; Pillow required. No screenshot masks or colour rescaling.
"""
import json
from pathlib import Path
import shutil
from PIL import Image
from automation_bridge import editor, engine


def main():
    root = Path(__file__).resolve().parents[1]
    output = root / "captures" / "rendering" / "hdr-validation"
    output.mkdir(parents=True, exist_ok=True)
    project = editor.open_project(root, start_if_needed=False)
    game = project.build_and_run(timeout=180)

    def cmd(name, data=None):
        return game.command(name, data or {})["result"]

    def sample_row(image, y):
        return [image.getpixel((int(image.width*(i+.5)/8), int(image.height*y))) for i in range(8)]

    def check(pixels, expected):
        for i, (rgb, value) in enumerate(zip(pixels, expected)):
            assert all(abs(c-value) <= 1 for c in rgb), (i, rgb, value)

    try:
        engine.wait_until(lambda: cmd("world.snapshot")["ready"], timeout=45)
        engine.wait_until(lambda: cmd("renderer.snapshot")["ready"], timeout=10)
        snapshot = cmd("renderer.snapshot")
        assert snapshot["pipeline"]["hdr"] and snapshot["pipeline"]["format"] == "rgba16f", snapshot
        cmd("capture.shot", {"name": "laboratory"})
        # Goldens from the reference neutral AgX curve, evaluated in double
        # precision. Different exposures catch lost HDR before tone mapping.
        goldens = {0.25: [0, 0, 5, 66, 143, 224, 239, 246],
                   1: [0, 0, 33, 128, 202, 248, 254, 255],
                   4: [0, 4, 86, 189, 239, 255, 255, 255]}
        results = {}
        for exposure, expected in goldens.items():
            cmd("renderer.configure", {"view": "hdr_probe", "exposure": exposure, "bloom": False})
            engine.wait_until(lambda: cmd("renderer.snapshot")["settings"]["exposure"] == exposure
                              and cmd("renderer.snapshot")["settings"]["view"] == "hdr_probe", timeout=5)
            path = output / f"probe-{exposure}.png"
            shutil.copyfile(game.screenshot(after_frames=3).path, path)
            with Image.open(path) as source:
                image = source.convert("RGB")
                raw, mapped, transfer = sample_row(image, 5/6), sample_row(image, .5), sample_row(image, 1/6)
            check(raw, [0, 0, 0, 1, 4, 32, 64, 112])
            check(mapped, expected)
            check(transfer, [10, 1, 118, 55, 150, 112, 40, 64])
            results[str(exposure)] = {"raw": raw, "agx": mapped, "transfer_filter_blend": transfer}
        cmd("capture.end")
        (output / "report.json").write_text(json.dumps({"renderer": snapshot, "probes": results}, indent=2)+"\n")
        print("PASS HDR >8, linear filtering, hardware alpha blend, world/weapon mix, sRGB knees and reference AgX at three exposures", flush=True)
    finally:
        game.close_engine()
        game.close()
    errors = [line for line in project.console.read().lines if "ERROR:" in line]
    assert not errors, "\n".join(errors)


if __name__ == "__main__":
    main()
