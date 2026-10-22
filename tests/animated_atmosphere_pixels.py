"""Within-backend GPU gates; never compare Metal bytes with WebGL bytes."""
import json
import sys
from pathlib import Path
from PIL import Image, ImageChops, ImageStat


def main():
    root = Path(sys.argv[1])
    results = {}

    def difference(a, b):
        first = Image.open(root / (a + ".png")).convert("RGB")
        second = Image.open(root / (b + ".png")).convert("RGB")
        assert first.size == second.size
        return sum(ImageStat.Stat(ImageChops.difference(first, second)).mean) / 3

    for prefix in ("sky", "environment", "fog"):
        delta = difference(prefix + "_zero", prefix + "_drift")
        assert delta > .015, (prefix, delta)
        restored = difference(prefix + "_zero", prefix + "_return")
        assert restored == 0, (prefix, restored)
        results[prefix] = {"drift_mean_rgb": delta, "restore_mean_rgb": restored}
    # The top atlas row contains linear BRDF coefficients. Weather must keep
    # these bytes, including the six repeated tiles and their padded edges.
    atlas = Image.open(root / "environment_zero.png").convert("RGB")
    lut_box = (0, 0, atlas.width, int(atlas.height / 9) - 1)
    lut = atlas.crop(lut_box)
    for name in ("environment_drift", "environment_return"):
        changed = Image.open(root / (name + ".png")).convert("RGB").crop(lut_box)
        assert ImageChops.difference(lut, changed).getbbox() is None, name
    tile_width = atlas.width // 6
    assert atlas.width == tile_width * 6
    first = lut.crop((2, 1, tile_width - 2, lut.height - 1))
    for face in range(1, 6):
        other = lut.crop((face * tile_width + 2, 1, (face + 1) * tile_width - 2, lut.height - 1))
        assert ImageChops.difference(first, other).getbbox() is None, face

    def coefficient(x, y):
        # Nearest screenshot pixel to an interior LUT texel; screenshot and
        # atlas dimensions differ, so allow two display steps at the endpoints.
        px = round((x + 1.5) / 396 * atlas.width - .5)
        py = round((1 - (8 * 66 + y + 1.5) / 594) * atlas.height - .5)
        return atlas.getpixel((px, py))

    smooth, rough = coefficient(63, 0), coefficient(63, 63)
    assert all(abs(a-b) <= 2 for a,b in zip(smooth, (255, 0, 0))), smooth
    assert 55 < rough[0] < 100, rough
    assert coefficient(3, 0)[1] > 180
    results["brdf"] = {"unchanged_by_weather": True, "identical_copies": 6,
                       "normal_smooth": smooth, "normal_rough": rough}
    delta = difference("cloud_shadow", "cloud_shadow_off")
    assert delta > .1, delta
    restored = difference("cloud_shadow", "cloud_shadow_return")
    assert restored == 0, restored
    results["cloud_shadow"] = {"toggle_mean_rgb": delta, "restore_mean_rgb": restored}
    for a, b in (("5", "12"), ("12", "19.2"), ("19.2", "20"), ("20", "21"), ("21", "1.5")):
        delta = difference("hour_" + a, "hour_" + b)
        assert delta > .5, (a, b, delta)
        results[a + "_to_" + b] = {"mean_rgb": delta}
    (root / "pixels.json").write_text(json.dumps(results, indent=2) + "\n")
    print("PASS 16 animated-atmosphere pixel gates", root)


if __name__ == "__main__":
    main()
