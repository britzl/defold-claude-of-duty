"""Check the paired images from the local_shadow_cache WebGL fixture.

python3 tests/local_shadow_cache_pixels.py --output build/local-shadow-cache-browser-validation
Requires Pillow and NumPy.
"""
import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image


def difference(reference, cached):
    a = np.asarray(Image.open(reference).convert('RGB'), dtype=np.int16)
    b = np.asarray(Image.open(cached).convert('RGB'), dtype=np.int16)
    diff = np.abs(a - b)
    result = {'mean_channel_difference': float(diff.mean()), 'max_channel_difference': int(diff.max()),
              'pixels_over_8_fraction': float((diff.max(axis=2) > 8).mean())}
    assert result['mean_channel_difference'] < .05 and result['pixels_over_8_fraction'] < .001, result
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=Path('build/local-shadow-cache-browser-validation'))
    root = parser.parse_args().output
    report = json.loads((root / 'report.json').read_text())
    assert not report['errors'], report['errors']
    assert report['result']['shots'] == 16
    results = {}
    for name in ('street', 'interior', 'courtyard', 'local_lights', 'foliage_local'):
        for view in (('scene', 'local_shadow') if name in ('local_lights', 'foliage_local') else ('scene',)):
            label = name + '_' + view
            results[label] = difference(root / (label + '_reference.png'), root / (label + '_cached.png'))
            for suffix, static, copies in (('_reference', 12, 0), ('_cached', 0, 1)):
                stats = report['shots'][label + suffix]['renderer']
                assert stats['local_shadow_static_draw_passes'] == static
                assert stats['local_shadow_copy_draw_passes'] == copies
            print('PASS', label, results[label])
    (root / 'pixel-report.json').write_text(json.dumps(results, indent=2) + '\n')


if __name__ == '__main__':
    main()
