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
    print("PASS 13 animated-atmosphere pixel gates", root)


if __name__ == "__main__":
    main()
