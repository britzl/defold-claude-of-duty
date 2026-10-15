"""Matched world-detail stills and frozen-scene resource accounting.
PYTHONPATH=automation-bridge-python:tests python3 tests/world_detail_capture.py
Requires Pillow and the open Defold editor. Owns and closes its engine.
"""
from dataclasses import asdict
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shutil
from PIL import Image, ImageChops
from automation_bridge import editor, engine
from render_baseline import source_fingerprint

ROOT=Path(__file__).resolve().parents[1]
OUTPUT=ROOT/'build/world-detail-native-validation'


def main():
    OUTPUT.mkdir(parents=True,exist_ok=True)
    project=editor.open_project(ROOT,start_if_needed=False)
    game=project.build_and_run(timeout=180)
    report={'engine':'defold','created_utc':datetime.now(timezone.utc).isoformat(),
            'source_sha256':source_fingerprint(),'shots':{}}
    def cmd(name,data=None): return game.command(name,data or {})['result']
    try:
        engine.wait_until(lambda: cmd('world.snapshot')['ready'],timeout=90)
        cmd('ai.configure',{'enabled':False})
        report['world']=cmd('world.snapshot')
        report['catalog']=cmd('capture.catalog')
        game.resize(1280,720);game.wait_frames(40)
        size=cmd('renderer.snapshot')
        game.resize(round(1280**2/size['width']),round(720**2/size['height']))
        engine.wait_until(lambda: (cmd('renderer.snapshot')['width'],cmd('renderer.snapshot')['height'])==(1280,720),timeout=15)
        for name in ('street','interior','courtyard','detail'):
            snapshot=cmd('capture.shot',{'name':name})
            game.wait_frames(40)
            path=OUTPUT/(name+'.png')
            shutil.copyfile(game.screenshot(after_frames=3).path,path)
            cmd('capture.shot',{'name':'interior' if name=='street' else 'street'})
            game.wait_frames(3)
            cmd('capture.shot',{'name':name});game.wait_frames(40)
            with Image.open(path) as a,Image.open(game.screenshot(after_frames=3).path) as b:
                assert a.size==b.size==(1280,720)
                assert ImageChops.difference(a.convert('RGB'),b.convert('RGB')).getbbox() is None,name
            costs=game.profiler.capture(frames=60,warmup_frames=10,timeout=30)
            report['shots'][name]={'status':'captured','image':path.name,'capture':snapshot,
                'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'repeat_identical':True,
                'renderer':cmd('renderer.snapshot'),'profile':{
                    'scope':'Frozen scene; submitted counters and CPU scopes, not sustained combat, GPU timing or process residency.',
                    'scopes':[asdict(s) for s in costs.scopes()[:16]],
                    'counters':[asdict(c) for c in costs.counters()]}}
            print('PASS matched still, exact repeat and profile',name,flush=True)
        cmd('capture.end')
        report['engine_health']=game.health()
        report['complete']=True
        (OUTPUT/'manifest.json').write_text(json.dumps(report,indent=2)+'\n')
    finally:
        game.close_engine();game.close()
    errors=[line for line in project.console.read().lines if 'ERROR:' in line]
    assert not errors,'\n'.join(errors)
    print('PASS clean shutdown',flush=True)


if __name__=='__main__': main()
