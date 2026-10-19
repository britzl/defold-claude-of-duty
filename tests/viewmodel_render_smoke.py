"""Frozen viewmodel repeats, arm lighting/materials and independent AA on Metal."""
import json
import shutil
from pathlib import Path
from PIL import Image, ImageChops, ImageStat
from automation_bridge import editor, engine
from render_baseline import source_fingerprint


def main():
    root=Path(__file__).resolve().parents[1]
    output=root/'build/viewmodel-render-validation';output.mkdir(parents=True,exist_ok=True)
    project=editor.open_project(root,start_if_needed=False)
    game=project.build_and_run(timeout=180)
    report={'sources':source_fingerprint(),'checks':{}}
    def cmd(name,data=None): return game.command(name,data or {})['result']
    def settle(): game.wait_frames(45)
    def save(name):
        path=output/(name+'.png');shutil.copyfile(game.screenshot(resolution_multiplier=.5).path,path)
        return Image.open(path).convert('RGB')
    def difference(a,b,arm=False):
        if arm:
            w,h=a.size
            box=(round(w*.25),round(h*.77),round(w*.43),round(h*.99))
            a,b=a.crop(box),b.crop(box)
        return sum(ImageStat.Stat(ImageChops.difference(a,b)).mean)/3
    try:
        engine.wait_until(lambda:cmd('world.snapshot')['ready'] and cmd('renderer.snapshot')['ready'],timeout=90)
        cmd('ai.configure',{'enabled':False})
        for shot in ['rifle_hip','rifle_ads','smg_hip','smg_ads','pistol_hip','pistol_ads','weapon_indoor']:
            cmd('capture.shot',{'name':shot});settle();base=save(shot)
            cmd('capture.shot',{'name':'street'});settle()
            cmd('capture.shot',{'name':shot});settle();again=save(shot+'-repeat')
            assert difference(base,again)==0,(shot,'repeat')
            report['checks'][shot]={'exact_repeat':True}
        for shot,key,arm in [('rifle_hip','combat_materials',True),('rifle_hip','weapon_aa',False),
                             ('weapon_indoor','interior_lighting',True)]:
            cmd('capture.shot',{'name':shot});settle();base=save(shot+'-'+key)
            cmd('renderer.configure',{key:False});settle();off=save(shot+'-'+key+'-off')
            delta=difference(base,off,arm)
            assert delta>.001,(shot,key,delta)
            cmd('renderer.configure',{key:True});settle();back=save(shot+'-'+key+'-return')
            assert difference(base,back)==0,(shot,key,'return')
            report['checks'][shot+'/'+key]={'difference':delta,'arm_crop':arm,'exact_return':True}
            print('PASS',shot,key,delta,flush=True)
        report['renderer']=cmd('renderer.snapshot')
    finally:
        game.close_engine();game.close()
        (output/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    errors=[line for line in project.console.read().lines if 'ERROR:' in line or 'WARNING:' in line]
    assert not errors,'\n'.join(errors)
    print('PASS seven exact still repeats and three presentation gates',flush=True)


if __name__=='__main__': main()
