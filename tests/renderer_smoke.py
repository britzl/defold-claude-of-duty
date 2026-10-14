"""Native GPU validation. Requires Automation Bridge and Pillow.

PYTHONPATH=automation-bridge-python python3 tests/renderer_smoke.py
Owns/closes the engine; writes review images to build/renderer-validation.
"""
import math
import shutil
from pathlib import Path
from PIL import Image, ImageChops, ImageStat
from automation_bridge import editor, engine
from materials_smoke import atlas_layout, atlas_stats, validate_channels


def main():
    root = Path(__file__).resolve().parents[1]
    output = root / "build" / "renderer-validation"
    output.mkdir(parents=True, exist_ok=True)
    project = editor.open_project(root, start_if_needed=False)
    game = project.build_and_run(timeout=180)

    def command(name, data=None):
        return game.command(name, data or {})["result"]

    def configure(**values):
        command("renderer.configure", values)
        engine.wait_until(lambda: all(command("renderer.snapshot")["settings"][k] == v
                                      for k, v in values.items()), timeout=5)
        game.wait_frames(3)

    def capture(name):
        # Native launches may lose focus while the editor compiles another target.
        command("ui.pause", {"paused": False})
        game.wait_frames(3)
        shot = game.screenshot(resolution_multiplier=.5)
        path = output / (name + ".png")
        shutil.copyfile(shot.path, path)
        print("SCREENSHOT", path, flush=True)
        return Image.open(path).convert("RGB")

    def region(image):
        w, h = image.size
        return image.crop((w//10, h//5, 9*w//10, 4*h//5))

    def difference(a, b):
        return sum(ImageStat.Stat(ImageChops.difference(region(a), region(b))).mean) / 3

    try:
        engine.wait_until(lambda: game.state("world").value["ready"], timeout=25)
        engine.wait_until(lambda: command("renderer.snapshot")["ready"], timeout=60)
        command("ai.configure", {"enabled": False})
        command("world.view", {"name": "street"})
        initial = command("renderer.snapshot")
        expected=atlas_stats()
        assert initial["bake_jobs"] == expected["jobs"] and initial["bake_draws"] == expected["draws"]
        assert initial["environment_faces"] == 6 and initial["local_light_count"] == 4
        assert initial["target_count"] == 12 and initial["shadow_size"] == 1024
        assert initial["atlas_width"] == expected["width"] and initial["atlas_height"] == expected["height"]
        assert initial["shadow_frames"] > 0

        for view in ("albedo", "normals", "material"):
            configure(view=view)
            image = capture(view)
            w, h = image.size
            for name, level, x, y, size in atlas_layout():
                if level != 0: continue
                patch = image.crop((round(w*(x+.15*size)/expected["width"]), round(h*(1-(y+.85*size)/expected["height"])),
                                    round(w*(x+.85*size)/expected["width"]), round(h*(1-(y+.15*size)/expected["height"]))))
                mean = ImageStat.Stat(patch).mean
                if view == "albedo":
                    assert 2 < min(mean) < 255, (name, mean)
                elif view == "normals":
                    assert 115 < mean[0] < 140 and 115 < mean[1] < 140 and mean[2] > 215, (name, mean)
                else:
                    validate_channels(name,mean)
        configure(view="environment")
        environment = capture("environment")
        assert min(ImageStat.Stat(region(environment)).stddev) > 8
        print("PASS generated albedo, tangent normals, material channels and six-face environment", flush=True)

        configure(view="scene")
        street = capture("street")
        configure(shadows=False)
        no_shadows = capture("street_without_shadows")
        delta = difference(street, no_shadows)
        assert delta > 1, delta
        configure(shadows=True, normal_maps=False)
        flat = capture("street_without_normals")
        normal_delta = difference(street, flat)
        assert normal_delta > .05, normal_delta
        configure(normal_maps=True)
        print("PASS sun shadow and normal-map contributions", delta, normal_delta, flush=True)

        command("world.view", {"name": "room"})
        game.wait_frames(4)
        room = capture("room")
        configure(local_lights=False)
        dark_room = capture("room_without_light")
        delta = difference(room, dark_room)
        assert delta > 1, delta
        configure(local_lights=True, exposure=.5)
        low = capture("room_low_exposure")
        configure(exposure=2)
        high = capture("room_high_exposure")
        assert sum(ImageStat.Stat(region(high)).mean) > sum(ImageStat.Stat(region(low)).mean) + 30
        configure(exposure=1)
        print("PASS room light and shared exposure", delta, flush=True)

        for name in ("e2_shop", "e2_upstairs", "e2_top"):
            command("world.view", {"name": name})
            game.wait_frames(4)
            lit = capture(name)
            configure(local_lights=False)
            dark = capture(name + "_without_light")
            delta = difference(lit, dark)
            assert delta > 1, (name, delta)
            configure(local_lights=True)
            assert command("renderer.snapshot")["local_light_count"] == 4
            print("PASS camera selects visible room light on", name, delta, flush=True)

        # Frozen soldier remains animated; collapse must also deform the shadow.
        command("world.view", {"name": "street"})
        command("ai.reset", {"position": {"x": 1, "y": .004, "z": 4}, "yaw": 0})
        configure(view="shadow")
        standing = capture("shadow_standing")
        command("gameplay.damage", {"target": "enemy_1", "amount": 1000, "source": "player"})
        engine.wait_until(lambda: command("ai.snapshot")["actors"][0]["death"] >= 1, timeout=5)
        collapsed = capture("shadow_collapsed")
        shadow_diff = ImageChops.difference(standing, collapsed).getchannel("R")
        changed_pixels = sum(shadow_diff.histogram()[2:])
        assert changed_pixels > 30, changed_pixels
        print("PASS animated skeleton changes the shadow silhouette", changed_pixels, flush=True)

        configure(view="scene")
        command("gameplay.restart")
        command("ai.configure", {"enabled": False})
        command("movement.reset", {"x": 0, "y": .01, "z": 4, "yaw": 0})
        game.wait_frames(45)
        capture("weapon_hip")
        command("weapons.drive", {"segments": [{"ticks": 100, "aim": True}]})
        engine.wait_until(lambda: command("weapons.result")["complete"], timeout=5)
        capture("weapon_ads")
        # Look at the sun to exercise bright-pass extraction, not only dim walls.
        command("movement.reset", {"x": 0, "y": .01, "z": 4, "yaw": math.atan2(.6, -.4)})
        command("movement.drive", {"segments": [{"ticks": 1, "look_y": math.atan2(.85, math.sqrt(.52))/.0022}]})
        engine.wait_until(lambda: command("movement.result")["complete"], timeout=5)
        game.wait_frames(4)
        bloom = capture("bloom")
        configure(bloom=False)
        no_bloom = capture("without_bloom")
        bloom_increase = ImageChops.subtract(region(bloom), region(no_bloom)).getchannel("R")
        brightened_pixels = sum(bloom_increase.histogram()[2:])
        assert brightened_pixels > 100, brightened_pixels
        configure(bloom=True)
        print("PASS isolated hip/ADS weapon pass and bloom contribution", brightened_pixels, flush=True)

        before = command("renderer.snapshot")
        game.resize(800, 500)
        engine.wait_until(lambda: command("renderer.snapshot")["resizes"] > before["resizes"], timeout=5)
        resized = command("renderer.snapshot")
        assert resized["width"] != before["width"] and resized["height"] != before["height"]
        assert resized["bloom_width"] == resized["width"]//4
        assert resized["bloom_height"] == resized["height"]//4
        assert resized["bake_draws"] == expected["draws"] and resized["target_count"] == 12
        game.resize(960, 640)
        command("world.view", {"name": "street"})
        game.wait_frames(8)
        capture("final_street")
        print("PASS resize retains baked resources; final stats", command("renderer.snapshot"), flush=True)
    finally:
        game.close_engine()
        game.close()
    errors = [line for line in project.console.read().lines if "ERROR:" in line]
    assert not errors, "\n".join(errors)
    print("PASS renderer build, pixel checks and clean shutdown", flush=True)


if __name__ == "__main__":
    main()
