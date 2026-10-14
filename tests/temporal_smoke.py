"""GPU checks for temporal history, moving surfaces and isolated weapon AA."""
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
    output=ROOT/'captures/rendering/temporal-validation';output.mkdir(parents=True,exist_ok=True)
    project=editor.open_project(ROOT,start_if_needed=False)
    game=project.build_and_run(timeout=180)
    report={'source_sha256':source_fingerprint()}
    def cmd(name,data=None): return game.command(name,data or {})['result']
    def stats(): return cmd('renderer.snapshot')
    def settle():
        game.wait_frames(36)
        if stats()['settings']['temporal_aa'] and stats()['settings']['view'] in ('scene','motion','history'):
            engine.wait_until(lambda:stats()['temporal_age']>=32,timeout=10)
    def shot(name,live=False):
        cmd('capture.shot',{'name':name,'temporal_live':live});settle()
    def config(**values):
        cmd('renderer.configure',values)
        engine.wait_until(lambda:all(stats()['settings'][k]==v for k,v in values.items()),timeout=5)
        settle()
    def save(name):
        path=output/(name+'.png');shutil.copyfile(game.screenshot(after_frames=1).path,path)
        return Image.open(path).convert('RGB')
    def resize(w,h):
        game.resize(w,h);game.wait_frames(35);s=stats()
        game.resize(round(w*w/s['width']),round(h*h/s['height']))
        engine.wait_until(lambda:(stats()['width'],stats()['height'])==(w,h),timeout=10)
    try:
        engine.wait_until(lambda:cmd('world.snapshot')['ready'] and stats()['ready'],timeout=70)
        resize(1280,720)
        assert stats()['target_count']==23
        for name in ('street','laboratory','shadow_cutout','weapon','ads'):
            shot(name);enabled=save(name)
            game.wait_frames(17);assert delta(enabled,save(name+'-held'))==0,'converged capture changed'
            config(temporal_aa=False);disabled=save(name+'-no-taa')
            difference=delta(enabled,disabled);assert .005<difference<15,(name,difference)
            config(temporal_aa=True);restored=save(name+'-restored')
            assert delta(enabled,restored)==0,(name,'nonrepeatable reset',delta(enabled,restored))
            if name in ('weapon','ads'):
                config(weapon_aa=False);no_aa=save(name+'-no-weapon-aa')
                weapon_delta=delta(enabled,no_aa);assert weapon_delta>.001,(name,weapon_delta)
                report[name+'_weapon_aa_difference']=weapon_delta
                # A weapon-independent world region must be exactly unchanged.
                assert delta(enabled.crop((0,0,1280,200)),no_aa.crop((0,0,1280,200)))==0
            report[name]={'taa_difference':difference,'repeat_identical':True}
            print('PASS',name,report[name],flush=True)
        shot('street');reference=save('return-before')
        shot('interior');shot('street');assert delta(reference,save('camera-return'))==0
        before=stats()['temporal_resets'];resize(800,502);settle()
        assert stats()['temporal_resets']>before
        resize(1280,720);settle();assert delta(reference,save('resize-return'))==0
        for view in ('motion','history'):
            config(view=view);image=save('static-'+view)
            if view=='motion':
                # Reprojection cancels jitter; static geometry has subpixel-zero velocity.
                pixels=list(image.crop((150,150,1100,600)).getdata())
                bad=sum(abs(r-128)>2 or abs(g-128)>2 for r,g,b in pixels)
                assert bad/len(pixels)<.025,(bad,len(pixels))
                report['static_velocity_bad_fraction']=bad/len(pixels)
            else:
                mean=ImageStat.Stat(image).mean[0];assert mean>70,mean
                report['history_weight_mean']=mean/255
        # Continuous camera motion retains history (unlike independent settled shots).
        shot('shadow_cutout',True);config(view='motion');before=stats()['temporal_resets']
        cmd('capture.play',{'playing':True});game.wait_frames(20)
        motion=save('camera-motion');cmd('capture.play',{'playing':False})
        pixels=list(motion.getdata());moving=sum(abs(r-128)>3 or abs(g-128)>3 for r,g,b in pixels)
        assert moving>1000,moving
        assert stats()['temporal_resets']==before
        report['camera_motion_pixels']=moving
        for endpoint in (120,0):
            cmd('capture.frame',{'frame':endpoint});cmd('capture.play',{'playing':True})
            game.wait_frames(6)
            assert 0<=cmd('capture.snapshot')['frame']<=120
            cmd('capture.play',{'playing':False})
        # Retain continuous history across a frame-addressed sweep for visual review.
        # Screenshot latency permits extra held frames; this is not a real-time movie.
        shot('shadow_cutout',True);samples=[]
        folder=output/'continuous-sweep';folder.mkdir(exist_ok=True)
        for frame in range(0,121,2):
            state=cmd('capture.frame',{'frame':frame})
            receipt=game.screenshot(after_frames=1)
            shutil.copyfile(receipt.path,folder/f'{frame//2:04d}.png')
            samples.append(state)
        report['continuous_sweep']={'samples':samples,'timing':'frame-addressed with continuous history; held frames depend on capture latency'}
        # Actual rigid actor movement plus skinned gait, viewed by a stationary camera.
        cmd('capture.end');cmd('ui.pause',{'paused':False});cmd('movement.reset',{'x':0,'y':.01,'z':10,'yaw':0})
        cmd('ai.reset',{'position':{'x':1,'y':.004,'z':-3},'yaw':0})
        cmd('ai.patrol',{'points':[{'x':1,'y':.004,'z':-3},{'x':3,'y':.004,'z':-3}]})
        config(view='motion');game.wait_frames(18)
        actor=save('soldier-motion')
        pixels=list(actor.getdata());moving=sum(b>240 and (abs(r-128)>3 or abs(g-128)>3) for r,g,b in pixels)
        assert moving>25,(moving,cmd('ai.snapshot'))
        report['soldier_motion_pixels']=moving
        before=stats()['temporal_resets'];cmd('gameplay.restart');game.wait_frames(35)
        assert stats()['temporal_resets']>before
        before=stats()['temporal_resets'];cmd('movement.reset',{'x':0,'y':.01,'z':10,'yaw':0});game.wait_frames(35)
        assert stats()['temporal_resets']>before
        # Continuous, frozen-gameplay A/B cost: temporal resolve stays active.
        shot('street',True);costs={}
        for label,enabled in (('enabled',True),('disabled',False)):
            config(temporal_aa=enabled,weapon_aa=enabled)
            sample=game.profiler.capture(frames=90,warmup_frames=15,timeout=30)
            costs[label]={'renderer':stats(),'scopes':[asdict(v) for v in sample.scopes()[:20]],'counters':[asdict(v) for v in sample.counters()]}
        report['costs']=costs
        cmd('capture.end')
        errors=[v for v in project.console.read().lines if 'ERROR:' in v];assert not errors,'\n'.join(errors)
    finally:
        (output/'report.json').write_text(json.dumps(report,indent=2)+'\n')
        game.close_engine();game.close()
    print('PASS temporal validation',flush=True)
if __name__=='__main__': main()
