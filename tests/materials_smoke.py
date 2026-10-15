"""Validate the actual GPU mip pyramid, including every wrapped border.

PYTHONPATH=automation-bridge-python python3 tests/materials_smoke.py
Requires Pillow and Lua. Owns/closes the Defold engine.
"""
from pathlib import Path
import subprocess
import json
from PIL import Image, ImageChops, ImageStat
from automation_bridge import editor, engine

ROOT = Path(__file__).resolve().parents[1]


def atlas_stats(quality="medium"):
    values=subprocess.check_output(["lua","-e",'local a=require("game.render.surface_atlas").new("'+quality+'") print(a.width,a.height,a.job_count,a.draw_count)'],cwd=ROOT,text=True)
    return dict(zip(("width","height","jobs","draws"),map(int,values.split())))


def validate_channels(name, mean):
    # Glass remains dielectric and smooth; exposed steel is metallic; oxide is
    # insulating. Recipe averages must agree with those physical distinctions.
    assert mean[2] > 120, (name,"occlusion",mean)
    assert mean[0] > (5 if name == "glass" else 30), (name,"roughness",mean)
    if name == "metal_brushed": assert mean[1] > 200, (name,mean)
    elif name == "corrugated": assert 60 < mean[1] <= 255, (name,mean)
    elif name in ("metal_painted","metal_rust"): assert 0 <= mean[1] < 245, (name,mean)
    else: assert mean[1] < 10, (name,"dielectric",mean)
    if name == "glass": assert mean[0] < 100, (name,"glass gloss",mean)


def atlas_layout(quality="medium"):
    rows = subprocess.check_output(["lua", "-e", '''
local a=require("game.render.surface_atlas").new("QUALITY")
for _,s in ipairs(a.surfaces) do for level,r in ipairs(s.rects) do
 print(s.name,level-1,r.x,r.y,r.size)
end end
'''.replace('QUALITY',quality)], cwd=ROOT, text=True)
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
                validate_channels(name,base)
        print("PASS", view, len(layout), "mip regions retain energy and wrapped borders", flush=True)
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
        engine.wait_until(lambda: cmd("renderer.snapshot")["ready"], timeout=60)
        cmd("capture.shot", {"name": "laboratory"})
        stats = cmd("renderer.snapshot")
        expected=atlas_stats(stats["material_quality"])
        assert stats["bake_jobs"] == expected["jobs"] and stats["bake_draws"] == expected["draws"]
        assert stats["target_count"] == 43 and stats["peak_target_bytes"] > stats["target_bytes"]
        width, height = stats["atlas_width"], stats["atlas_height"]
        # Page through 1024-pixel windows, avoiding desktop window-size limits.
        game.resize(1024, 1024);game.wait_frames(35)
        size=cmd("renderer.snapshot")
        game.resize(round(1024**2/size["width"]),round(1024**2/size["height"]))
        engine.wait_until(lambda: (cmd("renderer.snapshot")["width"],cmd("renderer.snapshot")["height"]) == (1024,1024),timeout=10)
        images={}
        columns=(width+1023)//1024
        for view in ("albedo", "normals", "material"):
            combined=Image.new("RGB",(width,height))
            for row in range((height+1023)//1024):
                for column in range(columns):
                    cmd("renderer.configure",{"view":view,"atlas_page":row*columns+column+1});game.wait_frames(5)
                    shot=game.screenshot()
                    image=Image.open(shot.path).convert("RGB")
                    assert image.size==(1024,1024),image.size
                    combined.paste(image,(column*1024,height-(row+1)*1024))
            combined.save(output/(view+".png"));images[view]=combined
        (output/"stats.json").write_text(json.dumps(stats,indent=2)+"\n")
        validate_maps(images, atlas_layout())
    finally:
        game.close_engine(); game.close()
    errors = [line for line in project.console.read().lines if "ERROR:" in line]
    assert not errors, "\n".join(errors)
    print("PASS reference material maps, mip filtering, temporary resource release and clean shutdown", flush=True)


if __name__ == "__main__":
    main()
