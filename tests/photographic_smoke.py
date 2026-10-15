"""Step 12 GPU pixels, adaptive exposure, capture determinism and resource tiers."""
import json, math, shutil
from pathlib import Path
from dataclasses import asdict
from PIL import Image, ImageChops, ImageStat
from automation_bridge import editor, engine
from render_baseline import source_fingerprint
ROOT=Path(__file__).resolve().parents[1]
def delta(a,b): return sum(ImageStat.Stat(ImageChops.difference(a,b)).mean)/3

def main():
    out=ROOT/'captures/rendering/photographic-validation';out.mkdir(parents=True,exist_ok=True)
    project=editor.open_project(ROOT,start_if_needed=False);game=project.build_and_run(timeout=180)
    report={'source_sha256':source_fingerprint(),'checks':{},'tiers':{}}
    def cmd(name,data=None):return game.command(name,data or {})['result']
    def stats():return cmd('renderer.snapshot')
    def settle():
        game.wait_frames(42)
        if stats()['settings']['temporal_aa'] and stats()['settings']['view']=='scene':
            engine.wait_until(lambda:stats()['temporal_age']>=32,timeout=15)
    def config(**values):
        cmd('renderer.configure',values);game.wait_frames(3)
        engine.wait_until(lambda:all(stats()['settings'][k]==v for k,v in values.items()),timeout=5);settle()
    def shot(name,live=False):cmd('capture.shot',{'name':name,'temporal_live':live});settle()
    def save(name):
        path=out/(name+'.png');shutil.copyfile(game.screenshot(after_frames=1).path,path)
        return Image.open(path).convert('RGB')
    def compare(name,option,value=0):
        shot(name);a=save(name+'-'+option);original=stats()['settings'][option]
        config(**{option:value});b=save(name+'-'+option+'-off');difference=delta(a,b)
        assert difference>.0001,(name,option,difference)
        config(**{option:original});assert delta(a,save(name+'-'+option+'-return'))==0
        report['checks'][name+'/'+option]={'difference':difference,'exact_return':True}
        print('PASS',name,option,difference,flush=True)
    try:
        engine.wait_until(lambda:cmd('world.snapshot')['ready'] and stats()['ready'],timeout=90)
        game.resize(640,360);game.wait_frames(40)
        s=stats();game.resize(round(1280*640/s['width']),round(720*360/s['height']));game.wait_frames(35)
        for name,option in [('street','grade_strength'),('interior','grade_strength'),('sunset','grade_strength'),('night','grade_strength'),
            ('weapon_fire','bloom_strength'),('street','vignette'),('street','grain'),('detail','sharpen'),('rifle_ads','ads_dof')]:compare(name,option)
        shot('weapon_fire');config(view='bloom');bloom=save('flash-bloom')
        assert max(ImageStat.Stat(bloom).mean)>1
        # All levels carry energy; broader levels spread it over more pixels.
        for level in range(1,6):
            config(bloom_level=level);image=save('bloom-level-'+str(level))
            assert max(image.getextrema())[1]>1,(level,image.getextrema())
        config(bloom_level=0)
        # Both the accumulated exposure and target are visualized as log2(E) in [-2,2].
        for name in ['street','interior','night','sky_daylight']:
            shot(name);config(auto_exposure=True,view='exposure');im=save(name+'-meter')
            pixel=im.getpixel((640,360));multiplier=2**(pixel[0]/255*4-2);target=2**(pixel[1]/255*4-2)
            limits=stats()['exposure_limits'];assert limits[0]-.02<=multiplier<=limits[1]+.02,(name,multiplier,limits)
            assert abs(multiplier-target)<.03,(name,multiplier,target)
            report['checks'][name+'/exposure']={'multiplier':multiplier,'target':target,'limits':limits}
        shot('street');config(view='grade');grade=save('generated-grade')
        # Reference LUT endpoints, avoiding inter-slice sampling at atlas edges.
        assert max(grade.getpixel((1,719)))<20
        assert min(grade.getpixel((1278,1)))>245
        report['checks']['grade']={'black':grade.getpixel((1,719)),'white':grade.getpixel((1278,1))}
        # Static world ignores camera jitter in motion blur; weapon never enters lens pass.
        shot('rifle_ads');a=save('ads-stable');config(motion_blur=0);b=save('ads-no-motion')
        assert delta(a,b)==0,delta(a,b)
        # A real continuous camera sweep exercises velocity at each quality.
        shot('street',True);cmd('capture.play',{'playing':True});game.wait_frames(60)
        save('moving');assert stats()['lens_draw_passes']==1
        cmd('capture.play',{'playing':False});game.wait_frames(50)
        assert cmd('capture.snapshot')['simulation_tick']==cmd('gameplay.snapshot')['tick']
        shot('street');base=save('before-resize');game.resize(1279,719);settle();save('odd-size')
        game.resize(1280,720);settle();assert delta(base,save('resized-return'))==0
        for tier in ['low','medium','high']:
            shot('rifle_ads',True);config(photographic_quality=tier)
            costs=game.profiler.capture(frames=90,warmup_frames=10,timeout=30)
            report['tiers'][tier]={'renderer':stats(),'scopes':[asdict(x) for x in costs.scopes()[:18]],
                'counters':[asdict(x) for x in costs.counters()], 'scope':'CPU submission; GPU timers measured separately in WebGL.'}
            save('tier-'+tier)
        assert report['tiers']['low']['renderer']['target_bytes']<report['tiers']['medium']['renderer']['target_bytes']<report['tiers']['high']['renderer']['target_bytes']
        for _ in range(3):
            config(photographic_quality='low');config(photographic_quality='high')
            assert stats()['target_count']==43
        cmd('capture.end');cmd('ui.focus',{'focused':True});cmd('ui.pause',{'paused':False});cmd('ai.configure',{'enabled':False})
        game.wait_frames(45);assert stats()['pipeline']['exposure_mode']=='adaptive_bounded'
        cmd('ui.pause',{'paused':True});game.wait_frames(35);time=stats()['grain_time'];game.wait_frames(35)
        assert stats()['grain_time']==time and stats()['exposure_draw_passes']==0
        report['live']=stats()
        errors=[line for line in project.console.read().lines if 'ERROR:' in line or 'WARNING:' in line]
        assert not errors,'\n'.join(errors)
    finally:
        (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');game.close_engine();game.close()
    print('PASS photographic native validation',flush=True)
if __name__=='__main__':main()
