"""GPU gates for cascaded shadows; owns the native Metal engine it builds."""
import json
import math
import shutil
from pathlib import Path
from PIL import Image, ImageChops, ImageStat
from automation_bridge import editor, engine

ROOT=Path(__file__).resolve().parents[1]

def cutout_samples(image):
    """Project known panel holes/solid cells along the sun onto the ground.

    Three unobstructed pairs distinguish true cutout shadows from an opaque
    rectangle or a wholly missing caster, independent of display resolution.
    """
    eye=(5,3.8,7);target=(2,1.1,3)
    forward=[target[i]-eye[i] for i in range(3)]
    length=math.sqrt(sum(x*x for x in forward));forward=[x/length for x in forward]
    right=[-forward[2],0,forward[0]]
    length=math.sqrt(sum(x*x for x in right));right=[x/length for x in right]
    up=[right[1]*forward[2]-right[2]*forward[1],right[2]*forward[0]-right[0]*forward[2],right[0]*forward[1]-right[1]*forward[0]]
    def pixel(point):
        delta=[point[i]-eye[i] for i in range(3)]
        depth=sum(delta[i]*forward[i] for i in range(3))
        scale=image.height/(2*math.tan(math.radians(29))*depth)
        x=round(image.width/2+sum(delta[i]*right[i] for i in range(3))*scale)
        y=round(image.height/2-sum(delta[i]*up[i] for i in range(3))*scale)
        return image.getpixel((x,y))[0]
    result=[]
    for x in (1.05,1.35,1.65):
        hole=pixel((x+.6*2.21/.85,0,2.25-.4*2.21/.85))
        solid=pixel((x+.15+.6*2.21/.85,0,2.4-.4*2.21/.85))
        assert hole>180 and solid<120,(x,hole,solid)
        result.append({'hole':hole,'solid':solid})
    return result

def main():
    output=ROOT/'captures/rendering/shadow-validation';output.mkdir(parents=True,exist_ok=True)
    project=editor.open_project(ROOT,start_if_needed=False)
    game=project.build_and_run(timeout=180)
    report={}
    def cmd(name,data=None): return game.command(name,data or {})['result']
    def configure(**changes):
        cmd('renderer.configure',changes)
        engine.wait_until(lambda: all(cmd('renderer.snapshot')['settings'][k]==v for k,v in changes.items()),timeout=5)
        game.wait_frames(4)
    def shot(name):
        snapshot=cmd('capture.shot',{'name':name});game.wait_frames(35);return snapshot
    def save(name):
        path=output/(name+'.png');shutil.copyfile(game.screenshot(after_frames=3).path,path)
        return Image.open(path).convert('RGB')
    def delta(a,b): return sum(ImageStat.Stat(ImageChops.difference(a,b)).mean)/3
    def resize(w,h):
        game.resize(w,h);game.wait_frames(35);stats=cmd('renderer.snapshot')
        game.resize(round(w*w/stats['width']),round(h*h/stats['height']))
        engine.wait_until(lambda: (cmd('renderer.snapshot')['width'],cmd('renderer.snapshot')['height'])==(w,h),timeout=5)
    try:
        engine.wait_until(lambda:cmd('world.snapshot')['ready'],timeout=45)
        engine.wait_until(lambda:cmd('renderer.snapshot')['ready'],timeout=60)
        resize(1280,720)
        initial=cmd('renderer.snapshot')
        assert initial['shadow_cascades']==4 and initial['shadow_atlas_size']==2048
        assert initial['target_count']==9 and initial['shadow_splits']==[8,22,52,120]
        assert initial['shadow_draw_passes']==8
        for name in ('street','interior','shadow_distance','shadow_cutout','shadow_remote'):
            shot(name);default=save(name)
            configure(shadows=False);disabled=save(name+'-disabled')
            difference=delta(default,disabled)
            assert difference>.05,(name,difference)
            configure(shadows=True);assert ImageChops.difference(default,save(name+'-restored')).getbbox() is None
            configure(view='cascades',bloom=False);save(name+'-cascades')
            configure(view='shadow_visibility');visibility=save(name+'-visibility')
            report[name]={'shadow_difference':difference,'exact_toggle_restore':True}
            if name=='shadow_cutout': report[name]['projected_coverage_samples']=cutout_samples(visibility)
            print('PASS shadow contribution and exact restore',name,difference,flush=True)
        shot('shadow_distance');configure(view='shadow',bloom=False)
        atlas=save('atlas')
        w,h=atlas.size
        quadrants=[]
        for y in (0,h//2):
            for x in (0,w//2):
                histogram=atlas.crop((x,y,x+w//2,y+h//2)).getchannel('R').histogram()
                written=sum(histogram[:250]);assert written>100,(x,y,written)
                quadrants.append(written)
        report['atlas_written_pixels']=quadrants
        configure(shadows=False)
        assert save('atlas-disabled').getextrema()==((255,255),)*3
        configure(shadows=True)
        assert ImageChops.difference(atlas,save('atlas-restored')).getbbox() is None
        # Camera movement, teleport, different FOV, and resize must not retain old
        # cascade transforms or rebake generated materials/environment.
        for name in ('shadow_remote','ads','interior'):
            shot(name)
        shot('shadow_distance');configure(view='shadow',bloom=False)
        assert ImageChops.difference(atlas,save('atlas-camera-return')).getbbox() is None
        texels=cmd('renderer.snapshot')['shadow_texels']
        for frame in (0,1,2,3,4,5,30,60,90,120):
            cmd('capture.frame',{'frame':frame});game.wait_frames(4)
            save('atlas-motion-'+str(frame))
            assert cmd('renderer.snapshot')['shadow_texels']==texels
        cmd('capture.frame',{'frame':0});game.wait_frames(4)
        assert ImageChops.difference(atlas,save('atlas-motion-return')).getbbox() is None
        resize(800,600);shot('shadow_remote');save('remote-4x3')
        resize(1280,720);shot('shadow_distance');configure(view='shadow',bloom=False)
        assert ImageChops.difference(atlas,save('atlas-resize-return')).getbbox() is None
        final=cmd('renderer.snapshot')
        assert final['target_count']==9 and final['bake_draws']==initial['bake_draws']
        assert final['shadow_draw_passes']==4
        report['renderer']=final
        report['camera_return_exact']=True
        cmd('capture.end')
    finally:
        (output/'report.json').write_text(json.dumps(report,indent=2)+'\n')
        game.close_engine();game.close()
    errors=[line for line in project.console.read().lines if 'ERROR:' in line]
    assert not errors,'\n'.join(errors)
    print('PASS cascaded atlas, coverage, toggles, camera/resize returns and clean shutdown',flush=True)

if __name__=='__main__': main()
