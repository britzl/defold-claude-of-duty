"""Step 11 native pixel gates, production-event lifecycle and bounded costs."""
import json
import shutil
from pathlib import Path
from dataclasses import asdict
from PIL import Image, ImageChops, ImageStat
from automation_bridge import editor, engine
from render_baseline import source_fingerprint
ROOT=Path(__file__).resolve().parents[1]
def delta(a,b): return sum(ImageStat.Stat(ImageChops.difference(a,b)).mean)/3

def main():
    output=ROOT/'captures/rendering/combat-validation';output.mkdir(parents=True,exist_ok=True)
    project=editor.open_project(ROOT,start_if_needed=False)
    game=project.build_and_run(timeout=180)
    report={'source_sha256':source_fingerprint(),'checks':{}}
    def cmd(name,data=None): return game.command(name,data or {})['result']
    def stats(): return cmd('renderer.snapshot')
    def settle():
        game.wait_frames(42)
        if cmd('capture.snapshot')['active'] and stats()['settings']['temporal_aa']:
            engine.wait_until(lambda:stats()['temporal_age']>=32,timeout=15)
    def config(**values):
        cmd('renderer.configure',values)
        engine.wait_until(lambda:all(stats()['settings'][k]==v for k,v in values.items()),timeout=5)
        settle()
    def shot(name): cmd('capture.shot',{'name':name});settle()
    def save(name):
        path=output/(name+'.png');shutil.copyfile(game.screenshot(after_frames=1).path,path)
        return Image.open(path).convert('RGB')
    def compare(shot_name,option,minimum=.002):
        shot(shot_name);a=save(shot_name+'-'+option)
        config(**{option:False});b=save(shot_name+'-'+option+'-off')
        d=delta(a,b);assert d>minimum,(shot_name,option,d)
        config(**{option:True});c=save(shot_name+'-'+option+'-return')
        assert delta(a,c)==0,(shot_name,option,'return',delta(a,c))
        report['checks'][shot_name+'/'+option]={'difference':d,'exact_return':True}
        print('PASS',shot_name,option,d,flush=True)
    try:
        engine.wait_until(lambda:cmd('world.snapshot')['ready'] and stats()['ready'],timeout=90)
        game.resize(640,360);game.wait_frames(40)
        s=stats();game.resize(round(1280*640/s['width']),round(720*360/s['height']));game.wait_frames(35)
        for name in ['rifle_hip','rifle_ads','smg_hip','smg_ads','pistol_hip','pistol_ads','weapon_indoor']:
            compare(name,'combat_materials')
        compare('weapon_indoor','interior_lighting')
        compare('weapon_fire','combat_effects')
        compare('combat_effects','combat_effects')
        compare('combat_effects','soft_particles')
        compare('combat_effects','impact_decals')
        compare('combat_glass','glass')
        compare('combat_glass','combat_effects')
        shot('combat_effects')
        base=save('effects-before-resize')
        game.resize(1279,719);settle();save('effects-odd-size')
        game.resize(1280,720);settle();assert delta(base,save('effects-resized-return'))==0
        # Follow the same static FX through a continuous camera sweep; no TAA
        # history contains them, and no simulation tick advances.
        cmd('capture.shot',{'name':'combat_effects','temporal_live':True});game.wait_frames(40)
        tick=cmd('capture.snapshot')['simulation_tick']
        for frame in range(0,121,20):
            cmd('capture.frame',{'frame':frame});game.wait_frames(2);save('effects-motion-'+str(frame))
        assert cmd('capture.snapshot')['simulation_tick']==tick
        shot('combat_effects');report['renderer']=stats();report['fx_fixture']=cmd('combat_fx.snapshot')
        cmd('capture.end');cmd('gameplay.restart');cmd('ai.configure',{'enabled':False})
        cmd('ui.focus',{'focused':True});cmd('ui.pause',{'paused':False})
        cmd('weapons.range');cmd('movement.reset',{'x':5,'y':.01,'z':40,'yaw':0})
        game.wait_frames(15)
        cmd('weapons.drive',{'segments':[{'ticks':300,'aim':True,'fire':True}]})
        engine.wait_until(lambda:cmd('combat_fx.snapshot')['impacts']>3,timeout=15)
        save('live-fire')
        sample=game.profiler.capture(frames=90,warmup_frames=5,timeout=30)
        report['live_cost']={'scopes':[asdict(v) for v in sample.scopes()[:20]],'counters':[asdict(v) for v in sample.counters()],
            'scope':'90 native frames while firing into concrete, not a sustained GPU benchmark.'}
        engine.wait_until(lambda:cmd('weapons.result')['complete'],timeout=20)
        state=cmd('combat_fx.snapshot');assert state['impacts']>3 and 0<state['decals']<=48 and state['shots']>0,state
        report['real_fire']=state
        cmd('ui.pause',{'paused':True});game.wait_frames(5)
        frozen=cmd('combat_fx.snapshot');game.wait_frames(35);assert frozen==cmd('combat_fx.snapshot')
        save('impact-decals')
        for _ in range(4):
            cmd('gameplay.restart');game.wait_frames(3)
            s=cmd('combat_fx.snapshot');assert s['particles']==0 and s['decals']==0 and s['meshes']==220 and s['buffers']==1,s
        # Freeze a real skinned soldier close to the camera and compare its
        # bind-space surfaces; animation/health/hit volumes remain production.
        cmd('ai.configure',{'enabled':False});cmd('ai.reset',{'position':{'x':0,'y':.01,'z':7.5},'yaw':3.14159265})
        cmd('movement.reset',{'x':0,'y':.01,'z':10,'yaw':0});cmd('ui.pause',{'paused':False});game.wait_frames(15)
        cmd('capture.shot',{'name':'street','actors':True});settle()
        a=save('soldier');config(combat_materials=False);b=save('soldier-flat')
        assert delta(a,b)>.002;report['checks']['soldier/materials']={'difference':delta(a,b)}
        config(combat_materials=True);assert delta(a,save('soldier-return'))==0
        cmd('capture.end')
        errors=[v for v in project.console.read().lines if 'ERROR:' in v or 'WARNING:' in v]
        assert not errors,'\n'.join(errors)
    finally:
        (output/'report.json').write_text(json.dumps(report,indent=2)+'\n')
        game.close_engine();game.close()
    print('PASS step 11 native rendering and lifecycle',flush=True)
if __name__=='__main__':main()
