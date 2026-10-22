"""Validate the focused weapon AA suite from validate_rendering_browser.mjs."""
import json
from pathlib import Path
import sys
from PIL import Image, ImageChops, ImageStat


def main():
    root = Path(sys.argv[1])
    report = json.loads((root / 'report.json').read_text())
    assert not report['errors'] and report['result']['shots'] == 30
    results = {}
    for name in report['shots']:
        if name.endswith(('_off', '_return')):
            continue
        def opened(suffix):
            return Image.open(root / (name + suffix + '.png')).convert('RGB')
        base, off, restored = opened(''), opened('_off'), opened('_return')
        delta = ImageChops.difference(base, off)
        difference = sum(ImageStat.Stat(delta).mean) / 3
        assert difference > .001, (name, difference)
        assert ImageChops.difference(base, restored).getbbox() is None, (name, 'return')
        assert delta.crop((0, 0, base.width, base.height // 4)).getbbox() is None, (name, 'world')
        state = report['shots'][name]['renderer']
        assert state['weapon_aa_draw_passes'] == 1
        assert report['shots'][name + '_off']['renderer']['weapon_aa_draw_passes'] == 0
        if name.endswith('_scaled'):
            assert state['width'] % 2 == 1 and state['height'] % 2 == 1, state
        results[name] = {'aa_mean_difference': difference, 'exact_return': True, 'world_unchanged': True}
    assert len(results) == 10
    (root / 'pixels.json').write_text(json.dumps(results, indent=2) + '\n')
    print('PASS ten weapon AA cases: contribution, exact returns and world isolation')


if __name__ == '__main__':
    main()
