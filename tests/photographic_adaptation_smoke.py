"""Real camera transitions exercise exposure lag, pause, and Photo menu controls."""
import json,shutil
from pathlib import Path
from PIL import Image
from automation_bridge import editor,engine
from render_baseline import source_fingerprint
ROOT=Path(__file__).resolve().parents[1]
def main():
    output=ROOT/'captures/rendering/photographic-adaptation';output.mkdir(parents=True,exist_ok=True)
    project=editor.open_project(ROOT,start_if_needed=False);game=project.build_and_run(timeout=180)
    report={'source_sha256':source_fingerprint(),'samples':[]}
    def cmd(name,data=None):return game.command(name,data or {})['result']
    def save(name):
        path=output/(name+'.png');shutil.copyfile(game.screenshot(after_frames=1).path,path)
        return Image.open(path).convert('RGB')
    def resume():
        # Native OS focus changes can arrive while the automation client runs.
        state=cmd('ui.snapshot')
        if not state['focused']:cmd('ui.focus',{'focused':True})
        if state['paused']:cmd('ui.pause',{'paused':False})
    try:
        engine.wait_until(lambda:cmd('world.snapshot')['ready'] and cmd('renderer.snapshot')['ready'],timeout=90)
        game.resize(1280,720);cmd('ai.configure',{'enabled':False});cmd('ui.focus',{'focused':True});cmd('ui.pause',{'paused':False})
        cmd('movement.reset',{'x':0,'y':.01,'z':10,'yaw':0})
        # Aimed pistol leaves the meter's centre visible during the sky transition.
        cmd('weapons.drive',{'segments':[{'ticks':2000,'weapon_pistol':True,'aim':True}]})
        cmd('renderer.configure',{'view':'exposure','auto_exposure':True});game.wait_frames(60)
        resets=cmd('renderer.snapshot')['temporal_resets']
        for label,direction in [('sky',4),('ground',-4)]:
            resume()
            cmd('movement.drive',{'segments':[{'ticks':180,'look_y':direction,'aim':True}]})
            for i in range(12):
                resume();game.wait_frames(4);im=save(label+'-'+str(i))
                if cmd('ui.snapshot')['paused']:
                    resume();game.wait_frames(4);im=save(label+'-'+str(i))
                r,g,_=im.getpixel((im.width//2,im.height//2))
                report['samples'].append({'direction':label,'exposure':2**(r/255*4-2),'target':2**(g/255*4-2),
                    'pitch':cmd('gameplay.snapshot')['pitch'],'time':cmd('gameplay.snapshot')['elapsed']})
            engine.wait_until(lambda:cmd('movement.result')['complete'],timeout=10)
        values=report['samples']
        # Sky deweighting deliberately limits this scene's target swing (~.11).
        # A .1 span is still several diagnostic codes; lag must exist both ways.
        assert max(s['target'] for s in values)-min(s['target'] for s in values)>.1,values
        # Two display codes exceed quantization; screenshot latency can miss
        # the peak lag, so test its direction rather than one exact trajectory.
        assert any(s['exposure']-s['target']>.03 for s in values),values
        assert any(s['target']-s['exposure']>.03 for s in values),values
        for direction in ('sky','ground'):
            last=[s for s in values if s['direction']==direction][-1]
            assert abs(last['exposure']-last['target'])<.04,last
        assert all(.63<=s['exposure']<=1.83 and .63<=s['target']<=1.83 for s in values),values
        # Each movement.drive explicitly leaves inspection mode and resets once.
        # Continuous camera updates must not add cuts within either segment.
        after=cmd('renderer.snapshot')['temporal_resets']
        report['history_resets']={'before':resets,'after':after,'expected_drives':2}
        assert after==resets+2,'Continuous camera movement added an unexpected reset'
        cmd('ui.pause',{'paused':True});game.wait_frames(40)
        assert cmd('renderer.snapshot')['exposure_draw_passes']==0
        cmd('renderer.configure',{'view':'scene'});game.wait_frames(40)
        cmd('ui.focus',{'focused':True})
        game.click(game.element(name_exact='tab_photo',visible=True));game.wait_frames(5)
        assert game.element(name_exact='setting_photographic_quality',visible=True)
        game.click(game.element(name_exact='setting_photographic_quality',visible=True));game.wait_frames(35)
        assert cmd('renderer.snapshot')['settings']['photographic_quality']=='low'
        save('photo-menu-low')
        game.click(game.element(name_exact='setting_auto_exposure',visible=True));game.wait_frames(35)
        assert not cmd('renderer.snapshot')['settings']['auto_exposure']
        report['pause_and_menu']='passed'
        assert not [x for x in project.console.read().lines if 'ERROR:' in x or 'WARNING:' in x]
    finally:
        (output/'report.json').write_text(json.dumps(report,indent=2)+'\n');game.close_engine();game.close()
    print('PASS continuous exposure adaptation, pause and Photo menu')
if __name__=='__main__':main()
