"""Validate the actual GPU mip pyramid, including every wrapped border.

PYTHONPATH=automation-bridge-python python3 tests/materials_smoke.py
Requires Pillow and Lua. Owns/closes the Defold engine.
"""
from pathlib import Path
import subprocess
from PIL import Image, ImageChops, ImageStat
from automation_bridge import editor, engine

ROOT = Path(__file__).resolve().parents[1]


def atlas_layout():
    rows = subprocess.check_output(["lua", "-e", '''
local a=require "game.render.surface_atlas"
for _,s in ipairs(a.surfaces) do for level,r in ipairs(s.rects) do
 print(s.name,level-1,r.x,r.y,r.size)
end end
'''], cwd=ROOT, text=True)
    return [(name, *map(lambda v: int(float(v)), values))
            for name, *values in (line.split() for line in rows.splitlines())]


def validate_maps(images, layout):
    for view, image in images.items():
        means = {}
        for name, level, x, y, size in layout:
            # Screenshot Y increases downward; atlas Y increases upward.
            y = image.height-y-size-2
            core = image.crop((x+1, y+1, x+size+1, y+size+1))
            means[name, level] = ImageStat.Stat(core).mean
            for a, b in [((x,y+1,x+1,y+size+1), (x+size,y+1,x+size+1,y+size+1)),
                         ((x+size+1,y+1,x+size+2,y+size+1), (x+1,y+1,x+2,y+size+1)),
                         ((x+1,y,x+size+1,y+1), (x+1,y+size,x+size+1,y+size+1)),
                         ((x+1,y+size+1,x+size+1,y+size+2), (x+1,y+1,x+size+1,y+2))]:
                error = max(v[1] for v in ImageChops.difference(image.crop(a), image.crop(b)).getextrema())
                assert error <= 2, ("wrapped border", view, name, level, error)
            base = means[name, 0]
            assert max(abs(a-b) for a,b in zip(base, means[name, level])) < 5, ("mip energy", view, name, level, base, means[name, level])
            if view == "normals":
                assert 120 < base[0] < 135 and 120 < base[1] < 135 and base[2] > 215, (name, base)
            elif view == "material":
                assert base[0] > 70 and base[2] > 170, (name, base)
                assert base[1] > 100 if name == "metal" else base[1] < 10, (name, base)
        print("PASS", view, "all 62 mip regions retain energy and wrapped borders", flush=True)
    albedo = images["albedo"]
    for name, level, x, y, size in layout:
        if level == 0 and name in ("plaster", "concrete", "asphalt", "wood"):
            core = albedo.crop((x+1, albedo.height-y-size-1, x+size+1, albedo.height-y-1))
            assert min(ImageStat.Stat(core).stddev) > 2, (name, "missing albedo variation")


def main():
    output = ROOT / "captures/rendering/material-validation"
    output.mkdir(parents=True, exist_ok=True)
    project = editor.open_project(ROOT, start_if_needed=False)
    game = project.build_and_run(timeout=180)
    def cmd(name, values=None): return game.command(name, values or {})["result"]
    try:
        engine.wait_until(lambda: cmd("world.snapshot")["ready"], timeout=45)
        engine.wait_until(lambda: cmd("renderer.snapshot")["ready"], timeout=15)
        cmd("capture.shot", {"name": "laboratory"})
        stats = cmd("renderer.snapshot")
        assert stats["bake_jobs"] == 372 and stats["bake_draws"] == 558
        assert stats["target_count"] == 9 and stats["peak_target_bytes"] > stats["target_bytes"]
        width, height = stats["atlas_width"], stats["atlas_height"]
        # Capture two halves at 1:1: macOS clamps window height to the display.
        game.resize(width, height//2)
        engine.wait_until(lambda: cmd("renderer.snapshot")["width"] == width and cmd("renderer.snapshot")["height"] == height//2, timeout=10)
        images = {}
        for view in ("albedo", "normals", "material"):
            combined = Image.new("RGB", (width, height))
            for half in (1, 2):
                cmd("renderer.configure", {"view": view, "atlas_half": half}); game.wait_frames(5)
                shot = game.screenshot()
                image = Image.open(shot.path).convert("RGB")
                assert image.size == (width, height//2), image.size
                combined.paste(image, (0, height//2 if half == 1 else 0))
            combined.save(output / (view+".png"))
            images[view] = combined
        validate_maps(images, atlas_layout())
    finally:
        game.close_engine(); game.close()
    errors = [line for line in project.console.read().lines if "ERROR:" in line]
    assert not errors, "\n".join(errors)
    print("PASS reference material maps, mip filtering, temporary resource release and clean shutdown", flush=True)


if __name__ == "__main__":
    main()
