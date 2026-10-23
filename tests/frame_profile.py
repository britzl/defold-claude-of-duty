"""Capture current per-frame costs with Defold's built-in Remotery profiler.

PYTHONPATH=automation-bridge-python python3 tests/frame_profile.py \
    --output build/frame-profile
Requires an open Defold project. Owns and closes the engine it builds.
Records all available threads; main-thread elapsed scopes include waits and
instrumentation overhead. They are not release FPS or GPU duration estimates.
"""
import argparse
from collections import Counter
from dataclasses import asdict
from datetime import datetime, timezone
import gzip
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time

from automation_bridge import editor, engine
from automation_bridge.profiler import ProfilerCapture

ROOT = Path(__file__).resolve().parents[1]


def source_hashes():
    paths = [ROOT / 'game.project']
    for directory in ('game', 'main', 'render', 'world', 'weapons', 'soldiers', 'soldierpose'):
        paths.extend(p for p in (ROOT / directory).rglob('*') if p.is_file())
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(paths)}


def summarize(capture):
    frames = tuple(f for f in capture.frames if f.thread_name == 'Main' and not f.partial and f.root.name == 'Step')
    assert len(frames) >= 200, 'Insufficient complete Main/Step samples'
    main = ProfilerCapture(frames=frames, property_frames=capture.property_frames)
    durations = sorted(f.root.duration_us / 1000 for f in frames)
    gaps = [b.start_us - a.start_us for a, b in zip(frames, frames[1:])]
    return {
        'samples': len(frames), 'mean_ms': sum(durations) / len(frames),
        'p95_ms': durations[int(.95 * (len(frames) - 1))],
        'p99_ms': durations[int(.99 * (len(frames) - 1))], 'max_ms': max(durations),
        'sample_span_seconds': (frames[-1].end_us - frames[0].start_us) / 1e6,
        'mean_delivered_sample_spacing_ms': sum(gaps) / len(gaps) / 1000,
        'main_frames_excluded': sum(f.thread_name == 'Main' for f in capture.frames) - len(frames),
        'thread_sample_counts': dict(Counter(f.thread_name for f in capture.frames)),
        'scopes': [dict(asdict(s), ms_per_frame=s.total.total_us / len(frames) / 1000,
                        self_ms_per_frame=s.self.total_us / len(frames) / 1000,
                        calls_per_frame=s.calls_total / len(frames)) for s in main.scopes(thread='Main')],
        'counters': [asdict(c) for c in capture.counters()],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--scenarios', nargs='+', choices=('standing', 'sprint', 'firing'),
                        default=['standing', 'sprint', 'firing'])
    parser.add_argument('--focus', action='store_true', help='Focus the engine window while profiling')
    parser.add_argument('--unattended', action='store_true', help='Ignore window focus callbacks in this debug profiling process')
    parser.add_argument('--pose-backends', nargs='+', choices=('lua', 'native'),
                        help='Compare pose backends in the same engine; reverse backend order on repetition two')
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    report = {'created_utc': datetime.now(timezone.utc).isoformat(),
              'revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
              'sources': source_hashes(), 'profiles': {},
              'method': 'Defold native debug Metal / Remotery, High quality, 1280x720. '
                        'Main/Step elapsed scopes include driver waits and profiler overhead. '
                        'AI damage disabled to keep the player alive. Two repetitions in reversed order.'}
    report['unattended'] = args.unattended
    report['pose_backends'] = args.pose_backends

    def save():
        (out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')

    project = editor.open_project(ROOT, start_if_needed=False)
    game = project.build_and_run(timeout=180, focus=args.focus)
    report['engine_binary_sha256'] = hashlib.sha256((ROOT / 'build/arm64-osx/dmengine').read_bytes()).hexdigest()

    def cmd(name, data=None):
        return game.command(name, data or {})['result']

    def state():
        return {n: cmd(n + '.snapshot') for n in ('gameplay', 'ai', 'renderer', 'weapons', 'ui', 'combat_fx')}

    def reset():
        cmd('gameplay.restart')
        cmd('ui.focus', {'focused': True})
        cmd('ui.pause', {'paused': False})
        cmd('ai.configure', {'damage_scale': 0})
        cmd('ui.configure', {'kind': 'quality', 'key': 'mode', 'value': 'high'})
        game.wait_frames(180, timeout=30)

    def record(name, driver=None, segments=None, pose_backend=None):
        before = state()
        power_before = subprocess.check_output(['pmset', '-g', 'batt'], text=True)
        print('START', name, flush=True)
        recording = game.profiler.start_recording(warmup_frames=30, max_frames=30000)
        try:
            if driver:
                cmd(driver + '.drive', {'segments': segments})
                engine.wait_until(lambda: cmd(driver + '.result')['complete'], timeout=60, interval=.5)
            else:
                # /frame polling triggers expensive scene traversal in this
                # bridge version. Listen only to Remotery during the capture.
                time.sleep(10)
        finally:
            capture = recording.stop()
            with gzip.open(out / (name + '-raw.json.gz'), 'wt') as stream:
                json.dump(asdict(capture), stream)
        after = state()
        # Preserve the receipts even when a window focus change invalidates a
        # run, so paused/dead captures cannot be mistaken for live measurements.
        (out / (name + '-state.json')).write_text(json.dumps(dict(before=before, after=after), indent=2) + '\n')
        for snapshot in (before, after):
            assert not snapshot['gameplay']['paused'] and snapshot['gameplay']['alive']
            assert snapshot['gameplay'].get('profile_unattended', False) == args.unattended
            if pose_backend:
                assert snapshot['gameplay']['pose_backend'] == pose_backend
            assert (snapshot['renderer']['output_width'], snapshot['renderer']['output_height']) == (1280, 720)
            quality = snapshot['ui']['quality']
            assert quality['mode'] == quality['active'] == 'high'
        assert after['gameplay']['tick'] > before['gameplay']['tick']
        assert len(after['ai']['actors']) == 6
        assert not any(a['recovery_failed'] for a in after['ai']['actors'])
        data = dict(summarize(capture), before=before, after=after, power_before=power_before,
                    power_after=subprocess.check_output(['pmset', '-g', 'batt'], text=True))
        if driver:
            data['drive'] = cmd(driver + '.result')
        report['profiles'][name] = data
        save()
        print(name, {k: data[k] for k in ('samples', 'mean_ms', 'p95_ms', 'thread_sample_counts')}, flush=True)
        print('TOP SELF', [(s['name'], round(s['self_ms_per_frame'], 3))
                          for s in sorted(data['scopes'], key=lambda s: -s['self_ms_per_frame'])[:12]], flush=True)

    scenarios = {
        'standing': (None, None),
        'sprint': ('movement', [{'ticks': 720, 'move_z': -1, 'sprint': True}, {'ticks': 240}]),
        'firing': ('weapons', [{'ticks': 360, 'aim': True, 'fire': True}, {'ticks': 360, 'reload': True},
                             {'ticks': 360, 'aim': True, 'fire': True}, {'ticks': 360, 'reload': True}]),
    }
    try:
        if args.unattended:
            cmd('profiling.configure', {'unattended': True})
        engine.wait_until(lambda: cmd('world.snapshot')['ready'] and cmd('renderer.snapshot')['ready'], timeout=90)
        report['health'] = game.health()
        game.resize(1280, 720)
        game.wait_frames(20, timeout=30)
        actual = cmd('renderer.snapshot')
        game.resize(round(1280 * 1280 / actual['output_width']), round(720 * 720 / actual['output_height']))
        game.wait_frames(30, timeout=30)
        for repetition, names in enumerate((args.scenarios, list(reversed(args.scenarios))), 1):
            for name in names:
                backends = args.pose_backends or [None]
                if repetition == 2:
                    backends = list(reversed(backends))
                for backend in backends:
                    if backend:
                        cmd('profiling.configure', {'unattended': args.unattended, 'pose_backend': backend})
                    reset()
                    prefix = backend + '-' if backend else ''
                    record(prefix + name + '-' + str(repetition), *scenarios[name], pose_backend=backend)
        assert source_hashes() == report['sources'], 'Production sources changed during profiling'
        report['complete'] = True
    finally:
        game.close_engine()
        game.close()
        lines = project.console.read().lines
        for line in lines:
            match = re.search(r'Defold Engine ([^ ]+) \(([^)]+)\)', line)
            if match:
                report['engine'] = {'version': match[1], 'revision': match[2]}
        (out / 'console.txt').write_text('\n'.join(lines) + '\n')
        report['console_errors'] = [line for line in lines if 'ERROR:' in line]
        save()
    assert not report['console_errors'], report['console_errors']
    print('PASS current frame profile', out, flush=True)


if __name__ == '__main__':
    main()
