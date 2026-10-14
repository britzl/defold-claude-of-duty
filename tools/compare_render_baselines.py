"""Build labelled side-by-side rendering comparisons from two capture manifests.

python3 tools/compare_render_baselines.py first/manifest.json second/manifest.json --output captures/rendering/comparison
Cross-engine images are compared visually; no pixel-similarity score is assigned.
"""
import argparse
import json
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageStat


def compare(first, second, output, first_label=None, second_label=None):
    manifests = [json.loads(path.read_text()) for path in (first, second)]
    output.mkdir(parents=True, exist_ok=False)
    same_engine = manifests[0]["engine"] == manifests[1]["engine"]
    labels = [first_label or manifests[0]["engine"], second_label or manifests[1]["engine"]]
    report = {"inputs": [str(first), str(second)], "comparison": "within-engine" if same_engine else "cross-engine",
              "note": "Cross-engine framing is adapted; lighting, geometry and generation differ.", "shots": {}}
    order = list(dict.fromkeys(name for manifest in manifests for name in manifest["shots"]))
    for name in order:
        canvas = Image.new("RGB", (1280, 400), "#20252b")
        draw = ImageDraw.Draw(canvas)
        images = []
        for column, (path, manifest) in enumerate(zip((first, second), manifests)):
            shot = manifest["shots"].get(name, {"status": "missing"})
            draw.text((column*640+12, 12), f"{labels[column]} | {name} | {shot['status']}", fill="white")
            if shot["status"] == "captured":
                with Image.open(path.parent / shot["image"]) as image:
                    full = image.convert("RGB")
                images.append(full)
                thumb = full.copy()
                thumb.thumbnail((640, 360))
                canvas.paste(thumb, (column*640, 40))
            else:
                draw.text((column*640+12, 90), shot.get("reason", "No image available"), fill="#d8c7a6")
        entry = {"image": name + ".jpg"}
        if same_engine and len(images) == 2 and images[0].size == images[1].size:
            difference = ImageChops.difference(*images)
            entry["identical"] = difference.getbbox() is None
            entry["mean_absolute_channel_difference"] = ImageStat.Stat(difference).mean
            entry["interpretation"] = "Diagnostic only: compare matching backend, camera, resolution and settings."
        report["shots"][name] = entry
        canvas.save(output / entry["image"], quality=95)
    (output / "manifest.json").write_text(json.dumps(report, indent=2) + "\n")
    print(output)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("first", type=Path)
    parser.add_argument("second", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--first-label")
    parser.add_argument("--second-label")
    args = parser.parse_args()
    compare(args.first.resolve(), args.second.resolve(), args.output.resolve(), args.first_label, args.second_label)
