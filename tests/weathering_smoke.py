"""A/B pixel gates for world-anchored weather, micro detail and parallax.

Uses the native Defold engine. Records deterministic near/far comparisons and
frame-addressed sweeps; never advances the simulation while capturing.
"""
from pathlib import Path
import json
import shutil
from PIL import Image, ImageChops, ImageStat
from automation_bridge import editor, engine

ROOT=Path(__file__).resolve().parents[1]


def main():
    output=ROOT/'captures/rendering/weathering-validation'
    output.mkdir(parents=True,exist_ok=True)
    project=editor.open_project(ROOT,start_if_needed=False)
    game=project.build_and_run(timeout=180)
    report={}
    def cmd(name,data=None): return game.command(name,data or {})['result']
    def save(name):
        shot=game.screenshot(after_frames=5)
        path=output/(name+'.png');shutil.copyfile(shot.path,path)
        return Image.open(path).convert('RGB')
    def difference(a,b): return sum(ImageStat.Stat(ImageChops.difference(a,b)).mean)/3
    try:
        engine.wait_until(lambda: cmd('world.snapshot')['ready'],timeout=45)
        engine.wait_until(lambda: cmd('renderer.snapshot')['ready'],timeout=60)
        cases=[('weathering_facade','weathering',.3),('micro_detail','micro_detail',.05),
               ('parallax_tile','parallax',.01)]
        for shot,feature,minimum in cases:
            cmd('capture.shot',{'name':shot});game.wait_frames(35)
            enabled=save(shot+'-on')
            cmd('renderer.configure',{feature:False});game.wait_frames(5)
            disabled=save(shot+'-off')
            delta=difference(enabled,disabled)
            assert delta>minimum,(feature,delta)
            cmd('renderer.configure',{feature:True});game.wait_frames(5)
            restored=save(shot+'-restored')
            assert ImageChops.difference(enabled,restored).getbbox() is None,feature
            report[feature]={'mean_pixel_change':delta,'exact_restore':True}
            print('PASS',feature,delta,'exact restore',flush=True)
        cmd('capture.shot',{'name':'weathering_far'});game.wait_frames(35)
        far=save('far-on')
        cmd('renderer.configure',{'micro_detail':False,'parallax':False});game.wait_frames(5)
        far_off=save('far-off')
        w,h=far.size
        # The wall is distant; the foreground floor deliberately retains detail.
        wall=(int(w*.35),int(h*.42),int(w*.65),int(h*.56))
        assert ImageChops.difference(far.crop(wall),far_off.crop(wall)).getbbox() is None,'Detail did not fade on the distant wall'
        print('PASS distant micro normals and parallax fade completely',flush=True)
        cmd('capture.shot',{'name':'weathering_facade'});game.wait_frames(35)
        original=save('anchored-start')
        tick=cmd('capture.snapshot')['simulation_tick']
        for frame in (15,30,45,60,75,90,105,120):
            cmd('capture.frame',{'frame':frame});save('facade-sweep-'+str(frame))
        cmd('capture.frame',{'frame':0})
        assert ImageChops.difference(original,save('anchored-return')).getbbox() is None
        assert cmd('capture.snapshot')['simulation_tick']==tick
        report['anchoring']='Exact pixels after sweep; frozen simulation'
        report['renderer']=cmd('renderer.snapshot')
        cmd('capture.end')
    finally:
        (output/'report.json').write_text(json.dumps(report,indent=2)+'\n')
        game.close_engine();game.close()
    errors=[line for line in project.console.read().lines if 'ERROR:' in line]
    assert not errors,'\n'.join(errors)
    print('PASS weathering, microdetail, parallax and anchored camera motion',flush=True)

if __name__=='__main__': main()
