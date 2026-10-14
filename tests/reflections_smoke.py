"""Step 9 GPU gates: reflection hits/fallback, glass, local shadows and restoration."""
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
    output=ROOT/'captures/rendering/reflections-validation';output.mkdir(parents=True,exist_ok=True)
    project=editor.open_project(ROOT,start_if_needed=False)
    game=project.build_and_run(timeout=180)
    report={'source_sha256':source_fingerprint(),'shots':{}}
    def cmd(name,data=None):return game.command(name,data or {})['result']
    def stats():return cmd('renderer.snapshot')
    def settle():
        game.wait_frames(40)
        if stats()['settings']['temporal_aa'] and stats()['settings']['view']=='scene':
            engine.wait_until(lambda:stats()['temporal_age']>=32,timeout=10)
    def config(**values):
        cmd('renderer.configure',values)
        engine.wait_until(lambda:all(stats()['settings'][k]==v for k,v in values.items()),timeout=5)
        settle()
    def shot(name):cmd('capture.shot',{'name':name});settle()
    def save(name):
        path=output/(name+'.png');shutil.copyfile(game.screenshot(after_frames=1).path,path)
        return Image.open(path).convert('RGB')
    try:
        engine.wait_until(lambda:cmd('world.snapshot')['ready'] and stats()['ready'],timeout=80)
        game.resize(640,360);game.wait_frames(35)
        s=stats();game.resize(round(1280*640/s['width']),round(720*360/s['height']));game.wait_frames(35)
        assert stats()['target_count']==23
        for name,feature in [('reflections','reflections'),('glass','glass'),('local_lights','local_shadows')]:
            shot(name);enabled=save(name)
            config(**{feature:False});disabled=save(name+'-off')
            difference=delta(enabled,disabled);assert difference>.01,(name,difference)
            config(**{feature:True});restored=save(name+'-restored')
            repeat=delta(enabled,restored);assert repeat==0,(name,'restoration',repeat)
            report['shots'][name]={'difference':difference,'repeat_identical':True,'renderer':stats()}
            print('PASS',name,difference,flush=True)
        shot('reflections');config(view='reflections');mask=save('reflection-confidence')
        hits=sum(r>20 for r,g,b in mask.getdata());assert hits>100,hits
        border=list(mask.crop((0,0,8,mask.height)).getdata())+list(mask.crop((mask.width-8,0,mask.width,mask.height)).getdata())
        assert max(r for r,g,b in border)<20,'Reflection failed to fade at screen edges'
        report['reflection_hit_pixels']=hits
        config(reflections=False,view='scene');fallback=save('environment-fallback')
        assert min(ImageStat.Stat(fallback).stddev)>5
        shot('local_lights');config(view='local_shadow');atlas=save('local-shadow-atlas')
        assert min(ImageStat.Stat(atlas).stddev)>10
        assert stats()['local_shadow_draw_passes']==12
        config(local_shadows=False);assert stats()['local_shadow_draw_passes']==0
        shot('glass');config(view='glass');save('glass-layer')
        # Frame-addressed camera sweep retains each diagnostic fixture for review.
        folder=output/'sweep';folder.mkdir(exist_ok=True)
        cmd('capture.shot',{'name':'reflections','temporal_live':True});game.wait_frames(40)
        for frame in range(0,121,10):
            cmd('capture.frame',{'frame':frame});game.wait_frames(1)
            shutil.copyfile(game.screenshot(after_frames=1).path,folder/f'{frame:03}.png')
        # Drive real weapon events and verify bounded transient light submission.
        cmd('capture.end');cmd('ui.pause',{'paused':False});cmd('ai.configure',{'enabled':False})
        cmd('movement.reset',{'x':0,'y':.01,'z':10,'yaw':0})
        cmd('gameplay.restart');cmd('ai.configure',{'enabled':False});cmd('ui.pause',{'paused':False})
        before=stats()['muzzle_light_frames']
        cmd('weapons.drive',{'segments':[{'ticks':120,'fire':True},{'ticks':30}]})
        engine.wait_until(lambda:cmd('weapons.result')['complete'],timeout=20)
        game.wait_frames(35)
        assert stats()['muzzle_light_frames']>before and stats()['muzzle_light_count']==0
        report['muzzle_light_frames']=stats()['muzzle_light_frames']-before
        cmd('gameplay.restart');game.wait_frames(35);assert stats()['muzzle_light_count']==0
        # Profile live temporal history, not the converged capture hold.
        costs={}
        for label,enabled in [('enabled',True),('disabled',False)]:
            cmd('capture.shot',{'name':'street','temporal_live':True})
            config(reflections=enabled,glass=enabled,local_shadows=enabled,muzzle_lights=enabled)
            sample=game.profiler.capture(frames=90,warmup_frames=15,timeout=30)
            costs[label]={'renderer':stats(),'scopes':[asdict(v) for v in sample.scopes()[:20]],'counters':[asdict(v) for v in sample.counters()]}
        report['costs']=costs
        cmd('capture.end');game.wait_frames(5)
        errors=list(dict.fromkeys(v for v in project.console.read().lines if 'ERROR:' in v or 'WARNING:' in v))
        assert not errors,'\n'.join(errors)
    finally:
        (output/'report.json').write_text(json.dumps(report,indent=2)+'\n')
        game.close_engine();game.close()
    print('PASS step 9 GPU validation',flush=True)
if __name__=='__main__':main()
