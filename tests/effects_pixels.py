"""Controlled within-backend pixel gates; never a cross-engine parity claim."""
import json
from pathlib import Path
import sys
from PIL import Image, ImageChops, ImageStat


def validate(folder):
    folder = Path(folder)
    checks = []
    def compare(a, b, minimum=None, maximum=None):
        left = Image.open(folder / (a + '.png')).convert('RGB')
        right = Image.open(folder / (b + '.png')).convert('RGB')
        assert left.size == right.size
        diff = ImageChops.difference(left, right)
        mean = sum(ImageStat.Stat(diff).mean) / 3
        if minimum is not None:
            assert mean > minimum, (a, b, mean, minimum)
        if maximum is not None:
            assert mean <= maximum, (a, b, mean, maximum)
        checks.append({'images': [a, b], 'mean_rgb_difference': mean,
                       'minimum': minimum, 'maximum': maximum})
    compare('surface_impacts', 'surface_impacts_off', minimum=.02)
    compare('surface_impacts', 'surface_impacts_return', maximum=0)
    compare('surface_impacts_return', 'surface_no_soft', minimum=.0001)
    # The neutral fullscreen warp can introduce sub-LSB filtering differences.
    compare('occluded_effects', 'occluded_effects_off', maximum=.015)
    compare('explosion', 'explosion_no_heat', minimum=.002)
    compare('explosion', 'explosion_heat_return', maximum=0)
    compare('scorch', 'scorch_off', minimum=.005)
    compare('glass_smoke', 'glass_smoke_no_glass', minimum=.005)
    (folder / 'pixels.json').write_text(json.dumps({'checks': checks}, indent=2) + '\n')
    print(f'PASS {len(checks)} effects pixel gates: {folder}')


if __name__ == '__main__':
    for folder in sys.argv[1:]:
        validate(folder)
