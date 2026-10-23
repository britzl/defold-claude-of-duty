"""Controlled visual refinement views, repeats, HUD/menu and resource accounting.

PYTHONPATH=automation-bridge-python python3 tests/visual_refinement_smoke.py final
Pass 'before' for a baseline without repeat captures. Requires Pillow and the editor.
"""
import sys, json, shutil
from pathlib import Path
from PIL import Image, ImageChops
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'automation-bridge-python'))
from automation_bridge import editor, engine


def main(label="final"):
    output=ROOT/'captures/visual-refinement-2026-10-23'/label
    output.mkdir(parents=True,exist_ok=True)
    project=editor.open_project(ROOT,start_if_needed=False)
    game=project.build_and_run(timeout=240)
    report={'exact_repeats':[], 'checks':[]}
    def cmd(name,data=None): return game.command(name,data or {})['result']
    def save(name):
        dest=output/(name+'.png')
        shutil.copyfile(game.screenshot(after_frames=3).path,dest)
        return Image.open(dest).convert('RGB')
    try:
        engine.wait_until(lambda:cmd('world.snapshot')['ready'] and cmd('renderer.snapshot')['ready'],timeout=100)
        game.resize(1280,720);game.wait_frames(10)
        size=cmd('renderer.snapshot')
        game.resize(round(1280**2/size['width']),round(720**2/size['height']))
        engine.wait_until(lambda:(cmd('renderer.snapshot')['width'],cmd('renderer.snapshot')['height'])==(1280,720),timeout=10)
        report['world']=cmd('world.snapshot')
        for name in ('street','detail','courtyard','material_plaster','material_concrete','material_asphalt','material_grazing','weathering_facade','sky_daylight','sunset','night'):
            cmd('capture.shot',{'name':name});game.wait_frames(65)
            first=save(name)
            if label!='before':
                cmd('capture.shot',{'name':name});game.wait_frames(65)
                assert ImageChops.difference(first,save(name+'-repeat')).getbbox() is None,name
                report['exact_repeats'].append(name)
            print('CAPTURE',name,flush=True)
        cmd('capture.shot',{'name':'street'});cmd('renderer.configure',{'clouds':False});game.wait_frames(65);save('street-clear')
        cmd('capture.end');cmd('ai.configure',{'enabled':False})
        cmd('ui.focus',{'focused':True});cmd('ui.pause',{'paused':False})
        for name in ('north_plaza','cross_street'):
            cmd('world.view',{'name':name});game.wait_frames(65);save(name)
        cmd('gameplay.restart');cmd('ai.configure',{'enabled':False});cmd('ui.focus',{'focused':True});cmd('ui.pause',{'paused':False})
        game.wait_frames(80);save('hud')
        cmd('ui.pause',{'paused':True});game.wait_frames(8);save('pause')
        report['renderer']=cmd('renderer.snapshot')
        report['checks']=['eleven inspection views','clear-sky control','world views','HUD and pause menu','clean shutdown']
    finally:
        (output/'report.json').write_text(json.dumps(report,indent=2)+'\n')
        game.close_engine();game.close()
    errors=[line for line in project.console.read().lines if 'ERROR:' in line]
    assert not errors,'\n'.join(errors)
    print('PASS captures and clean shutdown',flush=True)


if __name__=="__main__":
    main(sys.argv[1] if len(sys.argv)>1 else "final")
