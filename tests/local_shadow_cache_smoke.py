"""Compare cached room shadows against full redraws on the native GPU.

PYTHONPATH=automation-bridge-python python3 tests/local_shadow_cache_smoke.py
Owns/closes its engine. Draw counters are submissions, not GPU timing or FPS.
"""
import argparse
from dataclasses import asdict
import json
from pathlib import Path
import shutil

from automation_bridge import editor, engine
from render_baseline import source_fingerprint
from local_shadow_cache_pixels import difference

ROOT = Path(__file__).resolve().parents[1]


def check_moving_actors(cmd, game, configure, save, out, report):
    # Move a soldier through the local-light fixture. Its previous shadow
    # must disappear while the static geometry remains cached.
    cmd('ai.configure', {'enabled': False})
    cmd('capture.shot', {'name': 'local_lights', 'actors': True})
    cmd('renderer.configure', {'view': 'local_shadow', 'temporal_aa': False})
    for enabled in (False, True):
        configure(enabled)
        refreshes = cmd('renderer.snapshot')['local_shadow_cache_refreshes']
        previous = None
        for index, x in enumerate((53, 55, 54)):
            cmd('ai.reset', {'position': {'x': x, 'y': .1, 'z': 0}, 'yaw': 0})
            game.wait_frames(40)
            path = save(f'actor-{index}-' + ('cached' if enabled else 'reference'))
            if enabled:
                report['stills']['actor-' + str(index)] = difference(out / f'actor-{index}-reference.png', path)
                assert cmd('renderer.snapshot')['local_shadow_cache_refreshes'] == refreshes
            if previous:
                assert path.read_bytes() != previous.read_bytes(), 'Soldier shadow did not move'
            previous = path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'build/local-shadow-cache-validation')
    parser.add_argument('--skip-profile', action='store_true')
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    report = {'source_sha256': source_fingerprint(), 'stills': {}, 'profiles': []}
    project = editor.open_project(ROOT, start_if_needed=False)
    game = project.build_and_run(timeout=180, focus=False)

    def cmd(name, data=None):
        return game.command(name, data or {})['result']

    def configure(enabled):
        cmd('renderer.configure', {'local_shadow_cache': enabled})
        game.wait_frames(45)

    def save(name):
        path = out / (name + '.png')
        shutil.copyfile(game.screenshot(after_frames=3).path, path)
        return path

    def profile(name, enabled):
        capture = game.profiler.capture(frames=300, warmup_frames=20, timeout=30)
        draws = next(c for c in capture.counters() if c.name == 'DrawCalls')
        data = {'scene': name, 'cache': enabled, 'draw_calls': asdict(draws), 'renderer': cmd('renderer.snapshot')}
        report['profiles'].append(data)
        print('DRAWS', name, enabled, draws.values.avg, flush=True)
        return draws.values.avg

    try:
        engine.wait_until(lambda: cmd('world.snapshot')['ready'] and cmd('renderer.snapshot')['ready'], timeout=90)
        cmd('ui.configure', {'kind': 'quality', 'key': 'mode', 'value': 'high'})
        game.resize(1280, 720)
        game.wait_frames(40)
        size = cmd('renderer.snapshot')
        game.resize(round(1280 * 1280 / size['output_width']), round(720 * 720 / size['output_height']))
        game.wait_frames(40)
        assert (cmd('renderer.snapshot')['output_width'], cmd('renderer.snapshot')['output_height']) == (1280, 720)
        for name in ('street', 'interior', 'courtyard', 'local_lights', 'foliage_local'):
            for actors, view in ((False, 'scene'), (True, 'local_shadow')):
                cmd('capture.shot', {'name': name, 'actors': actors})
                cmd('renderer.configure', {'view': view})
                label = name + '-' + view
                paths, counts = [], []
                for enabled in (False, True):
                    configure(enabled)
                    paths.append(save(label + ('-cached' if enabled else '-reference')))
                    stats = cmd('renderer.snapshot')
                    assert stats['local_shadow_copy_draw_passes'] == int(enabled)
                    assert stats['local_shadow_static_draw_passes'] == (0 if enabled else 12)
                    assert stats['local_shadow_dynamic_draw_passes'] == (12 if actors else 0)
                    if view == 'scene' and not args.skip_profile:
                        counts.append(profile(name, enabled))
                report['stills'][label] = difference(*paths)
                if counts:
                    assert counts[1] < counts[0] - 20, counts
                print('PASS local shadow pixels', label, report['stills'][label], flush=True)
        # The real room selection changes while the camera traverses the map.
        # Keep the same actors frozen, with temporal AA disabled for comparisons.
        for enabled in (False, True):
            cmd('capture.shot', {'name': 'street', 'actors': True, 'temporal_live': True})
            cmd('renderer.configure', {'local_shadow_cache': enabled, 'temporal_aa': False, 'view': 'local_shadow'})
            for frame in (0, 30, 60, 90, 120):
                cmd('capture.frame', {'frame': frame})
                game.wait_frames(40)
                label = 'sweep-' + str(frame)
                path = save(label + ('-cached' if enabled else '-reference'))
                if enabled:
                    report['stills'][label] = difference(out / (label + '-reference.png'), path)
        check_moving_actors(cmd, game, configure, save, out, report)
        if not args.skip_profile:
            cmd('capture.end')
            cmd('ai.reset')
            cmd('ai.configure', {'enabled': True})
            cmd('ai.configure', {'damage_scale': 0})
            cmd('ui.focus', {'focused': True})
            cmd('ui.pause', {'paused': False})
            for enabled in (False, True, False, True):
                configure(enabled)
                profile('live-spawn', enabled)
            # Exercise changing actors and effects without freezing simulation.
            cmd('weapons.drive', {'segments': [{'ticks': 360, 'fire': True}, {'ticks': 360, 'reload': True}]})
            engine.wait_until(lambda: cmd('weapons.result')['complete'], timeout=30)
            assert cmd('renderer.snapshot')['local_shadow_dynamic_draw_passes'] == 12
        report['renderer'] = cmd('renderer.snapshot')
        report['complete'] = True
    finally:
        game.close_engine()
        game.close()
        report['console_errors'] = [line for line in project.console.read().lines if 'ERROR:' in line]
        (out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    assert not report['console_errors'], report['console_errors']
    print('PASS local shadow cache', out, flush=True)


if __name__ == '__main__':
    main()
