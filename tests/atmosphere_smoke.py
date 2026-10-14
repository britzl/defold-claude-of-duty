"""Step 10 native GPU gates: fixed skies, shared IBL, shafts, history and costs."""
import json
import shutil
from dataclasses import asdict
from pathlib import Path
from PIL import Image, ImageChops, ImageStat
from automation_bridge import editor, engine
from render_baseline import source_fingerprint
ROOT=Path(__file__).resolve().parents[1]
def delta(a,b): return sum(ImageStat.Stat(ImageChops.difference(a,b)).mean)/3

def main():
    output=ROOT/'captures/rendering/atmosphere-validation';output.mkdir(parents=True,exist_ok=True)
    project=editor.open_project(ROOT,start_if_needed=False)
    game=project.build_and_run(timeout=180)
    report={'source_sha256':source_fingerprint(),'shots':{}}
    def cmd(name,data=None): return game.command(name,data or {})['result']
    def stats(): return cmd('renderer.snapshot')
    def settle():
        game.wait_frames(40)
        if stats()['settings']['temporal_aa'] and stats()['settings']['view']=='scene':
            engine.wait_until(lambda:stats()['temporal_age']>=32,timeout=10)
    def config(**values):
        cmd('renderer.configure',values)
        engine.wait_until(lambda:all(stats()['settings'][k]==v for k,v in values.items()),timeout=8)
        settle()
    def shot(name): cmd('capture.shot',{'name':name});settle()
    def save(name):
        path=output/(name+'.png');shutil.copyfile(game.screenshot(after_frames=1).path,path)
        return Image.open(path).convert('RGB')
    try:
        engine.wait_until(lambda:cmd('world.snapshot')['ready'] and stats()['ready'],timeout=90)
        game.resize(640,360);game.wait_frames(35)
        s=stats();game.resize(round(1280*640/s['width']),round(720*360/s['height']));game.wait_frames(35)
        assert stats()['target_count']==23
        original=stats()['settings'];initial_bakes=stats()['bake_draws']
        for name in ['street','interior','sunset','night','sky_daylight','sky_sunset','sky_night','window_shafts','moon','weapon','ads']:
            shot(name);first=save(name)
            before=stats()['environment_updates']
            config(lighting='night' if stats()['settings']['lighting']!='night' else 'daylight')
            assert stats()['environment_updates']>before
            shot(name);returned=save(name+'-return')
            assert delta(first,returned)==0,(name,'preset return differs',delta(first,returned))
            report['shots'][name]={'identical_return':True,'renderer':stats(),'capture':cmd('capture.snapshot')}
            print('PASS atmosphere capture',name,flush=True)
        assert delta(Image.open(output/'street.png'),Image.open(output/'sunset.png'))>3
        assert delta(Image.open(output/'sunset.png'),Image.open(output/'night.png'))>3
        shot('sky_daylight');clouded=save('clouds-on')
        config(clouds=False);clear=save('clouds-off')
        report['cloud_difference']=delta(clouded,clear);assert report['cloud_difference']>.1
        config(clouds=True);assert delta(clouded,save('clouds-return'))==0
        config(view='environment_atlas');day_env=save('environment-daylight')
        config(lighting='sunset');sun_env=save('environment-sunset')
        config(lighting='night');night_env=save('environment-night')
        assert delta(day_env,sun_env)>1 and delta(sun_env,night_env)>1
        shot('window_shafts');config(view='fog_scatter',bloom=False)
        shadowed=save('shafts-shadowed')
        config(fog_shadows=False);unshadowed=save('shafts-unshadowed')
        report['shaft_shadow_difference']=delta(shadowed,unshadowed)
        assert report['shaft_shadow_difference']>.1
        assert sum(ImageStat.Stat(unshadowed).mean)>sum(ImageStat.Stat(shadowed).mean)
        config(fog_shadows=True);assert delta(shadowed,save('shafts-return'))==0
        shot('sunset');on=save('fog-on')
        config(volumetric_fog=False);analytic=save('fog-analytic');assert stats()['atmosphere_draw_passes']==1
        config(fog=False);off=save('fog-off');assert stats()['atmosphere_draw_passes']==0
        assert delta(on,off)>.1 and delta(analytic,off)>.1
        config(fog=True,volumetric_fog=True);assert delta(on,save('fog-return'))==0
        config(view='fog_transmittance');save('fog-transmittance')
        # Odd-sized targets and camera cuts must reconstruct correctly and return.
        shot('window_shafts');first=save('resize-before')
        game.resize(713,401);game.wait_frames(40)
        s=stats();assert s['fog_width']==(s['width']+1)//2 and s['fog_height']==(s['height']+1)//2
        save('resize-odd')
        game.resize(1280,720);settle()
        s=stats();game.resize(round(1280*1280/s["width"]),round(720*720/s["height"]));settle()
        assert delta(first,save('resize-return'))==0
        # Continuous history and deterministic, addressed camera motion.
        cmd('capture.shot',{'name':'window_shafts','temporal_live':True});settle()
        sweep=output/'sweep';sweep.mkdir(exist_ok=True)
        for frame in range(0,121,10):
            cmd('capture.frame',{'frame':frame});game.wait_frames(2)
            shutil.copyfile(game.screenshot(after_frames=1).path,sweep/f'{frame:03}.png')
        assert stats()['temporal_age']>32
        # Profile sustained resolve submission, excluding the one-time sky bake.
        report['costs']={}
        for label,enabled in [('enabled',True),('disabled',False)]:
            cmd('capture.shot',{'name':'street','temporal_live':True})
            config(fog=enabled)
            sample=game.profiler.capture(frames=90,warmup_frames=15,timeout=30)
            report['costs'][label]={'renderer':stats(),'scopes':[asdict(v) for v in sample.scopes()[:20]],'counters':[asdict(v) for v in sample.counters()]}
        assert stats()['bake_draws']==initial_bakes
        cmd('capture.end');game.wait_frames(35);assert stats()['settings']==original
        errors=list(dict.fromkeys(v for v in project.console.read().lines if 'ERROR:' in v or 'WARNING:' in v))
        assert not errors,'\n'.join(errors)
    finally:
        (output/'report.json').write_text(json.dumps(report,indent=2)+'\n')
        game.close_engine();game.close()
    print('PASS step 10 native GPU validation',flush=True)
if __name__=='__main__':main()
