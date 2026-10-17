"""Capture fresh-launch level creation with Defold's native Remotery profiler.

PYTHONPATH=automation-bridge-python python3 tests/loading_profile.py --output build/loading-profile/run-1
Requires a current native editor build (compile first after adding scopes).
Owns only the engine it launches; keeps raw samples and measured phase spans.
"""
import argparse
from dataclasses import asdict
from datetime import datetime, timezone
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import time
from automation_bridge import engine

ROOT = Path(__file__).resolve().parents[1]


def summarize(capture):
    frames = [f for f in capture.frames if f.thread_name == 'Main']
    scopes = [asdict(s) for s in capture.scopes(thread='Main')]
    loading = {}
    for frame in frames:
        for sample in frame.samples():
            if not (sample.name or '').startswith('loading.'):
                continue
            entry = loading.setdefault(sample.name, dict(calls=0, frames=0, total_ms=0,
                max_frame_ms=0, first_us=sample.start_us, last_us=sample.end_us))
            entry['calls'] += sample.call_count
            entry['frames'] += 1
            entry['total_ms'] += sample.duration_us / 1000
            entry['max_frame_ms'] = max(entry['max_frame_ms'], sample.duration_us / 1000)
            entry['first_us'] = min(entry['first_us'], sample.start_us)
            entry['last_us'] = max(entry['last_us'], sample.end_us)
    phases = sorted((name, entry) for name, entry in loading.items() if name.startswith('loading.world.'))
    phases.sort(key=lambda pair: pair[1]['first_us'])
    for i, (name, entry) in enumerate(phases):
        end = phases[i+1][1]['first_us'] if i+1 < len(phases) else entry['last_us']
        entry['wall_ms_to_next_phase'] = (end-entry['first_us'])/1000
    start = phases[0][1]['first_us'] if phases else None
    end = phases[-1][1]['last_us'] if phases else None
    return dict(frames=len(frames), partial_frames=sum(f.partial for f in frames),
        loading=loading, world_loading_wall_ms=(end-start)/1000 if phases else None,
        scopes=scopes, counters=[asdict(c) for c in capture.counters()])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--uncapped', action='store_true', help='Diagnostic: launch with display.swap_interval=0')
    parser.add_argument('--material-quality', choices=('low','medium','high'), default='medium')
    parser.add_argument('--backend', choices=('lua','native'), default='native')
    parser.add_argument('--verify', action='store_true', help='Compare every native shape with the Lua reference; not a performance run')
    parser.add_argument('--audio-backend', choices=('lua','native'), default='native')
    parser.add_argument('--verify-audio', action='store_true', help='Verify native audio and job ownership; not a performance run')
    parser.add_argument('--audio-fingerprints', action='store_true', help='Hash each generated WAV for backend comparisons')
    args = parser.parse_args()
    if args.verify_audio and args.audio_backend!='native': parser.error('--verify-audio requires --audio-backend native')
    out = args.output.resolve(); out.mkdir(parents=True, exist_ok=False)
    with socket.socket() as reserved:
        reserved.bind(('127.0.0.1', 0)); profiler_port = reserved.getsockname()[1]
    command = [str(ROOT/'build/arm64-osx/dmengine'), str(ROOT/'build/default/game.projectc'),
        f'--config=profiler.remotery_port={profiler_port}', f'--config=world_mesh.backend={args.backend}',
        f'--config=render.material_quality={args.material_quality}',
        f'--config=world_mesh.verify={int(args.verify)}',
        f'--config=audio_synthesis.backend={args.audio_backend}',
        f'--config=audio_synthesis.verify={int(args.verify_audio)}',
        f'--config=audio_synthesis.fingerprints={int(args.audio_fingerprints)}']
    if args.uncapped: command.append('--config=display.swap_interval=0')
    report = dict(created_utc=datetime.now(timezone.utc).isoformat(), command=command,
        method='Defold native debug Metal / Remotery Main thread elapsed scopes; not GPU timestamps. Fresh process, normal loading budgets.',
        sources={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest()
                 for directory in ('game','main','render','worldmesh','audiosynth') for p in sorted((ROOT/directory).rglob('*')) if p.is_file()},
        markers=[])
    report['sources']['game.project'] = hashlib.sha256((ROOT/'game.project').read_bytes()).hexdigest()
    game = recording = None
    started = time.monotonic()
    with (out/'engine.log').open('w') as log:
        process = subprocess.Popen(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT,
            env={**os.environ, 'DM_SERVICE_PORT':'dynamic'})
        try:
            def profiler_url():
                assert process.poll() is None, (out/'engine.log').read_text()
                match = re.search(r'Initialized Remotery \((ws://[^)]+)\)', (out/'engine.log').read_text())
                return match[1] if match else None
            url = engine.wait_until(profiler_url, timeout=20, interval=.005)
            recording = engine.ProfilerConnection.from_url(url).start_recording(
                thread='Main', max_frames=20000, close_on_stop=True)
            report['profiler_connected_seconds'] = time.monotonic()-started
            port = int(re.search(r'Engine service started on port (\d+)', (out/'engine.log').read_text())[1])
            game = engine.connect(port, profiler_url=url, timeout=30)
            previous = None
            while time.monotonic()-started < 120:
                assert process.poll() is None, (out/'engine.log').read_text()
                assert 'ERROR:' not in (out/'engine.log').read_text(), (out/'engine.log').read_text()
                marker = {key:game.command(key+'.snapshot', {})['result'] for key in ('world','audio','renderer','gameplay')}
                marker['wall_seconds'] = time.monotonic()-started
                marker['recorded_frames'] = recording.frame_count
                report['markers'].append(marker)
                state = (marker['world']['phase'], marker['audio']['ready'], marker['renderer'].get('ready'))
                if state != previous:
                    print('PHASE', round(marker['wall_seconds'],3),state,'frame',marker['gameplay']['frame'], flush=True)
                    previous = state
                if all(state[1:]) and marker['world']['ready'] and marker['world'].get('timings',{}).get('playable'): break
                time.sleep(.2)
            assert all(report['markers'][-1][key]['ready'] for key in ('world','audio','renderer')), 'Loading timed out'
            audio = report['markers'][-1]['audio']
            assert audio['synthesis_backend']==args.audio_backend
            assert audio['loaded']==76 and audio['bytes']==1627520
            if args.verify_audio:
                assert audio['verified']==76
                assert 'NATIVE_AUDIO_TEST PASS' in (out/'engine.log').read_text()
            game.wait_frames(3)
            capture = recording.stop(); recording = None
            with gzip.open(out/'raw.json.gz','wt') as stream: json.dump(asdict(capture),stream)
            report.update(summarize(capture))
            report['coverage'] = dict(
                note='Profiler attachment can miss initialization, early recipes and audio chunks; application timings cover the full load.',
                recipes_captured=report['loading'].get('loading.geometry.recipes',{}).get('calls',0),
                recipes_expected=report['markers'][-1]['world']['boxes']+1,
                shapes_captured=report['loading'].get('loading.mesh.shape',{}).get('calls',0),
                shapes_expected=report['markers'][-1]['world']['boxes'],
                audio_uploads_captured=report['loading'].get('loading.audio.upload',{}).get('calls',0),
                audio_uploads_expected=audio['loaded'])
            # Faster native generation may complete before attachment. Record
            # coverage honestly; application timings cover the entire load.
            report['mesh_fingerprints'] = []
            for offset in range(0,report['markers'][-1]['world']['batches'],16):
                report['mesh_fingerprints'].extend(game.command('world.mesh_fingerprints', {'offset':offset,'limit':16})['result']['batches'])
            report['health'] = game.health()
            report['complete'] = True
        finally:
            if recording:
                try:
                    capture = recording.stop()
                    with gzip.open(out/'incomplete-raw.json.gz','wt') as stream: json.dump(asdict(capture),stream)
                except Exception as error: report['capture_error'] = str(error)
            if game:
                game.close_engine(); game.close()
            if process.poll() is None:
                process.terminate()
            process.wait(timeout=10)
            report['console_issues'] = [line for line in (out/'engine.log').read_text().splitlines()
                                        if 'ERROR:' in line or 'WARNING:' in line]
            (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    assert not report['console_issues'], report['console_issues']
    print('WORLD WALL MS', report['world_loading_wall_ms'],flush=True)
    for name, stats in report['loading'].items():
        print(name, {key:round(value,3) if isinstance(value,float) else value for key,value in stats.items() if not key.endswith('_us')},flush=True)


if __name__ == '__main__': main()
