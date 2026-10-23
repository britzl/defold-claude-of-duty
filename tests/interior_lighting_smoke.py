"""Interior readability, night response and isolation on the production renderer.

PYTHONPATH=automation-bridge-python python3 tests/interior_lighting_smoke.py
Requires the project open in Defold, the automation bridge and Pillow.
"""
import json
import shutil
from pathlib import Path

from PIL import Image, ImageChops, ImageStat
from automation_bridge import editor, engine

ROOT = Path(__file__).resolve().parents[1]


def luminance(image, box):
    rgb = ImageStat.Stat(image.crop(box)).mean
    return sum(c * w for c, w in zip(rgb, (.2126, .7152, .0722)))


def main():
    output = ROOT / 'captures/rendering/interior-illumination'
    output.mkdir(parents=True, exist_ok=True)
    project = editor.open_project(ROOT, start_if_needed=False)
    game = project.build_and_run(timeout=180)
    report = {}

    def cmd(name, data=None):
        return game.command(name, data or {})['result']

    def shot(label, name='interior', **settings):
        cmd('capture.shot', {'name': name})
        cmd('renderer.configure', settings)
        game.wait_frames(65, timeout=20)
        path = output / (label + '.png')
        shutil.copyfile(game.screenshot(after_frames=3).path, path)
        return Image.open(path).convert('RGB')

    try:
        engine.wait_until(lambda: cmd('world.snapshot')['ready'] and cmd('renderer.snapshot')['ready'], timeout=90)
        game.resize(1280, 720)
        game.wait_frames(10)
        size = cmd('renderer.snapshot')
        game.resize(round(1280**2 / size['width']), round(720**2 / size['height']))
        engine.wait_until(lambda: (cmd('renderer.snapshot')['width'], cmd('renderer.snapshot')['height']) == (1280, 720), timeout=10)
        initial = cmd('renderer.snapshot')

        # Fixed exposure and frozen time isolate illumination from adaptation.
        lit = shot('day')
        ungated = shot('day-ungated', interior_lighting=False)
        doorway = (580, 330, 620, 400)
        assert ImageChops.difference(lit.crop(doorway), ungated.crop(doorway)).getbbox() is None
        assert ImageChops.difference(lit, shot('day-restored')).getbbox() is None

        sky = shot('day-sky-only', local_lights=False, fog=False)
        full_sky = shot('day-full-sky', local_lights=False, fog=False, interior_lighting=False)
        # The rear wall excludes the doorway and all direct lamp illumination.
        # The old 18% gate fails this relative readability floor. A remaining
        # upper bound ensures rooms still receive less skylight than outdoors.
        wall = (200, 285, 500, 445)
        room_mean, sky_mean = luminance(sky, wall), luminance(full_sky, wall)
        assert .45 < room_mean / sky_mean < .85, (room_mean, sky_mean)
        lamp = (730, 90, 1000, 280)
        assert luminance(lit, lamp) > luminance(sky, lamp) + 30
        report['day'] = {'room_luminance': room_mean, 'ungated_luminance': sky_mean,
                         'relative_readability': room_mean / sky_mean,
                         'doorway_unchanged': True, 'exact_restoration': True}
        print('PASS diffuse room readability, lamp contrast and exterior isolation', report['day'], flush=True)

        night = shot('night', lighting='night')
        unlit = shot('night-unlit', lighting='night', local_lights=False, fog=False)
        night_mean = luminance(unlit, wall)
        assert night_mean < room_mean * .5, (night_mean, room_mean)
        # This wall is outside direct lamp illumination. Reflected lamp light
        # must reveal it at night, and switching lamps off must remove that fill.
        lit_night_mean = luminance(night, wall)
        assert lit_night_mean > night_mean + 8, (lit_night_mean, night_mean)
        assert luminance(night, lamp) > luminance(unlit, lamp) + 30
        report['night'] = {'unlit_luminance': night_mean, 'lit_luminance': lit_night_mean, 'day_luminance': room_mean}
        print('PASS room fill follows night environment; practical lamps still illuminate', report['night'], flush=True)

        lab = shot('laboratory', name='laboratory')
        assert ImageChops.difference(lab, shot('laboratory-ungated', name='laboratory', interior_lighting=False)).getbbox() is None
        street = shot('street', name='street')
        shot('weapon-indoor', name='weapon_indoor')
        assert ImageChops.difference(street, shot('street-return', name='street')).getbbox() is None
        final = cmd('renderer.snapshot')
        assert final['target_count'] == initial['target_count']
        assert final['bake_draws'] == initial['bake_draws']
        report['renderer'] = final
        print('PASS laboratory isolation, capture round trip and resource reuse', flush=True)
        cmd('capture.end')
    finally:
        (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
        game.close_engine()
        game.close()
    errors = [line for line in project.console.read().lines if 'ERROR:' in line]
    assert not errors, '\n'.join(errors)
    print('PASS clean engine shutdown', flush=True)


if __name__ == '__main__':
    main()
