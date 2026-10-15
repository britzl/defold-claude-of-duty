"""Native GPU qualification of all material tiers and the four added recipes.

Requires a current native editor build, Pillow, Lua and Automation Bridge.
Owns its processes. Output: build/material-catalogue-validation/<quality>.
"""
import argparse
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
from PIL import Image, ImageChops, ImageStat
from automation_bridge import engine
from materials_smoke import atlas_layout, atlas_stats, validate_maps
from render_baseline import source_fingerprint

ROOT = Path(__file__).resolve().parents[1]
NAMES = ('sand', 'corrugated', 'burlap', 'foliage')
SHOTS = [f'material_{name}{suffix}' for name in NAMES for suffix in ('', '_far', '_grazing')]
SHOTS += ['foliage_back', 'foliage_shadow', 'foliage_local']


def delta(a, b):
    return sum(ImageStat.Stat(ImageChops.difference(a, b)).mean)/3


def leaf_fraction(image, distance):
    # Inner projected card bounds, excluding edge coverage and the floor below.
    scale = image.height/(2*math.tan(math.radians(22.5))*distance)
    rx, ry = min(image.width*.3, .9*scale), min(image.height*.3, 1.1*scale)
    crop = image.crop((round(image.width/2-rx), round(image.height/2-ry),
                       round(image.width/2+rx), round(image.height/2+ry)))
    # Front/back cards have +Z view normals. Exclude the ground visible
    # through holes when looking at the back of the card.
    covered = sum(120 <= r <= 135 and 120 <= g <= 135 and b > 245
                  for r,g,b in crop.getdata())/(crop.width*crop.height)
    assert .07 < covered < .5, ('missing leaves or opaque card', distance, covered)
    return covered


def capture_catalogue(game, cmd, output, motion=False):
    def configure(**values):
        cmd('renderer.configure', values)
        engine.wait_until(lambda: all(cmd('renderer.snapshot')['settings'][k] == v for k, v in values.items()), timeout=10)
        game.wait_frames(40)
    def select(name, live=False):
        cmd('capture.shot', {'name': name, 'temporal_live': live})
        game.wait_frames(40)
    def save(name, frames=2):
        path = output/(name+'.png')
        shutil.copyfile(game.screenshot(after_frames=frames).path, path)
        return Image.open(path).convert('RGB')
    game.resize(1280, 720);game.wait_frames(35)
    size = cmd('renderer.snapshot')
    game.resize(round(1280**2/size['width']), round(720**2/size['height']))
    engine.wait_until(lambda: (cmd('renderer.snapshot')['width'], cmd('renderer.snapshot')['height']) == (1280,720), timeout=10)
    report = {'shots': {}, 'coverage': {}, 'motion': {}}
    for name in SHOTS:
        select(name); first = save(name)
        select('street');select(name)
        repeat = save(name+'-repeat')
        assert delta(first,repeat) == 0, ('camera return',name,delta(first,repeat))
        (output/(name+'-repeat.png')).unlink()
        report['shots'][name] = {'repeat_identical': True}
        print('PASS', output.name, name, 'exact repeat', flush=True)
    for name, distance in [('material_foliage', 2.32), ('material_foliage_far',25.32), ('foliage_back',2.32)]:
        select(name);configure(view='geometry_normals')
        normals = save(name+'-geometry_normals')
        report['coverage'][name] = leaf_fraction(normals, distance)
        configure(view='depth');depth = save(name+'-depth')
        # Each pixel belongs either to geometry in BOTH prepass attachments or sky.
        assert all((d == (255,255,255)) == (n == (0,0,0)) for d,n in zip(depth.getdata(),normals.getdata()))
    assert abs(report['coverage']['material_foliage']-report['coverage']['foliage_back']) < .025
    assert abs(report['coverage']['material_foliage']-report['coverage']['material_foliage_far']) < .13
    for name, feature in [('foliage_shadow','shadows'), ('foliage_local','local_shadows')]:
        select(name); enabled = save(name+'-enabled')
        configure(**{feature:False}); disabled = save(name+'-disabled')
        assert delta(enabled,disabled) > .005, (name,'missing shadows')
        configure(**{feature:True}); restored = save(name+'-restored')
        assert delta(enabled,restored) == 0, (name,'shadow restore')
        report['shots'][name]['shadow_difference'] = delta(enabled,disabled)
    if motion:
        for name in ('material_sand_grazing','material_corrugated_grazing','material_burlap','material_foliage_far'):
            folder = output/(name+'-sweep');folder.mkdir(exist_ok=True)
            select(name,True)
            resets = cmd('renderer.snapshot')['temporal_resets']
            differences=[];previous=None
            for frame in range(121):
                cmd('capture.frame',{'frame':frame})
                frame_image=save(f'{folder.name}/{frame:04d}',2)
                if previous: differences.append(delta(previous,frame_image))
                previous=frame_image
            stats=cmd('renderer.snapshot')
            assert stats['temporal_resets']==resets, (name,'history reset during continuous sweep')
            assert max(differences)<25, (name,'motion discontinuity',max(differences))
            report['motion'][name]={'frames':121,'maximum_frame_difference':max(differences),
                'history_resets':0,'timing':'Frame-addressed with held frames; not a performance recording.'}
            print('PASS',output.name,name,'121-frame motion',flush=True)
    return report


def run(quality, output, motion):
    folder=output/quality;folder.mkdir(parents=True,exist_ok=True)
    report={'source_sha256':source_fingerprint()}
    game=None
    with (folder/'engine.log').open('w') as log:
        process=subprocess.Popen([str(ROOT/'build/arm64-osx/dmengine'),str(ROOT/'build/default/game.projectc'),
            '--config=render.material_quality='+quality,'--config=display.width=1024',
            '--config=display.height=1024','--config=display.high_dpi=0'],cwd=ROOT,
            stdout=log,stderr=subprocess.STDOUT,env={**os.environ,'DM_SERVICE_PORT':'dynamic'})
        try:
            def port():
                assert process.poll() is None,(folder/'engine.log').read_text()
                match=re.search(r'Engine service started on port (\d+)',(folder/'engine.log').read_text())
                return int(match[1]) if match else None
            game=engine.connect(engine.wait_until(port,timeout=25),timeout=30)
            def cmd(name,data=None): return game.command(name,data or {})['result']
            engine.wait_until(lambda:cmd('world.snapshot')['ready'] and cmd('renderer.snapshot')['ready'],timeout=120)
            def actors_ready():
                cmd('ui.focus',{'focused':True});cmd('ui.pause',{'paused':False})
                return len(cmd('ai.snapshot')['actors'])==6
            engine.wait_until(actors_ready,timeout=15)
            report['world']=cmd('world.snapshot')
            cmd('capture.shot',{'name':'laboratory'});game.wait_frames(40)
            game.resize(1024,1024);game.wait_frames(35)
            size=cmd('renderer.snapshot')
            game.resize(round(1024**2/size['width']),round(1024**2/size['height']))
            engine.wait_until(lambda:(cmd('renderer.snapshot')['width'],cmd('renderer.snapshot')['height'])==(1024,1024),timeout=10)
            stats=cmd('renderer.snapshot');expected=atlas_stats(quality)
            assert stats['bake_draws']==expected['draws'] and stats['surface_count']==19 and stats['target_count']==43
            width,height=stats['atlas_width'],stats['atlas_height'];columns=math.ceil(width/1024)
            assert (stats['width'],stats['height'])==(1024,1024)
            maps={}
            for view in ('albedo','normals','material','coverage'):
                combined=Image.new('RGB',(width,height))
                for row in range(math.ceil(height/1024)):
                    for column in range(columns):
                        cmd('renderer.configure',{'view':view,'atlas_page':row*columns+column+1})
                        image=Image.open(game.screenshot(after_frames=5).path).convert('RGB')
                        assert image.size==(1024,1024)
                        combined.paste(image,(column*1024,height-(row+1)*1024))
                combined.save(folder/(view+'.png'));maps[view]=combined
            validate_maps({k:v for k,v in maps.items() if k!='coverage'},atlas_layout(quality))
            mask=maps['coverage'];means=[]
            for name,level,x,y,size in atlas_layout(quality):
                if name=='foliage':
                    core=mask.crop((x+1,height-y-size-1,x+size+1,height-y-1))
                    mean=ImageStat.Stat(core).mean[0]/255;means.append(mean)
                    if level==0: assert .05<mean<.5 and core.getextrema()[0]==(0,255)
            assert max(means)-min(means)<.025,('leaf mask mip energy',means)
            report['mask_mip_means']=means
            report.update(capture_catalogue(game,cmd,folder,motion))
            report['renderer']=stats
        finally:
            (folder/'report.json').write_text(json.dumps(report,indent=2)+'\n')
            if game: game.close_engine();game.close()
            if process.poll() is None: process.terminate()
            process.wait(timeout=15)
    errors=[l for l in (folder/'engine.log').read_text().splitlines() if 'ERROR:' in l]
    assert not errors,'\n'.join(errors)
    print('PASS',quality,'catalogue maps, coverage, stills, shadows and cleanup',flush=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--quality',choices=['low','medium','high','all'],default='all')
    parser.add_argument('--motion',action='store_true')
    args=parser.parse_args()
    for quality in (('low','medium','high') if args.quality=='all' else (args.quality,)):
        run(quality,ROOT/'build/material-catalogue-validation',args.motion and quality=='medium')
