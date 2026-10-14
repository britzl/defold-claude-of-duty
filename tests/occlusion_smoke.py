"""Native GPU gates for world depth/normals, horizon AO and contact shadows.

Owns the engine; writes repeatable A/B images, motion and costs under captures.
"""
import json
import math
import shutil
from dataclasses import asdict
from pathlib import Path
from PIL import Image, ImageChops, ImageStat
from automation_bridge import editor, engine

ROOT=Path(__file__).resolve().parents[1]

def difference(a,b): return sum(ImageStat.Stat(ImageChops.difference(a,b)).mean)/3

def validate_buffers(depth,normals,ao,contact):
    """Sky must be unoccluded; every normal must encode a unit view vector."""
    sky=0;covered=0;dark=0;hits=0
    for d,n,a,c in zip(depth.getdata(),normals.getdata(),ao.getdata(),contact.getdata()):
        if d==(255,255,255):
            sky+=1
            assert a==(255,255,255) and c==(255,255,255),(d,n,a,c)
            assert n==(0,0,0),n
        else:
            covered+=1
            length=sum((x/255*2-1)**2 for x in n)**.5
            assert .98<length<1.02,(n,length)
            dark+=a[0]<230;hits+=c[0]<240
            assert a[0]>=37,a # bounded visibility, not black dirt
    assert covered>1000 and dark>100 and hits>20,(covered,dark,hits)
    return dict(sky=sky,covered=covered,ao_pixels=dark,contact_pixels=hits)

def projection(eye,target,fov,image):
    def unit(v):
        length=math.sqrt(sum(x*x for x in v));return [x/length for x in v]
    forward=unit([target[i]-eye[i] for i in range(3)])
    right=unit([-forward[2],0,forward[0]])
    up=[right[1]*forward[2]-right[2]*forward[1],right[2]*forward[0]-right[0]*forward[2],right[0]*forward[1]-right[1]*forward[0]]
    def project(point):
        delta=[point[i]-eye[i] for i in range(3)];depth=sum(delta[i]*forward[i] for i in range(3))
        scale=image.height/(2*math.tan(math.radians(fov/2))*depth)
        return (round(image.width/2+sum(delta[i]*right[i] for i in range(3))*scale),
                round(image.height/2-sum(delta[i]*up[i] for i in range(3))*scale)),depth
    return project, [right[1],up[1],-forward[1]]

def fixture_samples(depth,normals,ao,contact):
    project,floor_normal=projection((7.5,1.7,5.3),(4.8,.4,2.1),60,depth)
    samples={}
    for name,point in [('foot',(6.28,0,3.08)),('sun_contact',(6.32,0,2.92)),('open_floor',(6.6,0,3.5))]:
        pixel,z=project(point)
        expected_depth=255*math.log2(1+z)/math.log2(501)
        assert abs(depth.getpixel(pixel)[0]-expected_depth)<2,(name,pixel,expected_depth)
        expected_normal=[(v*.5+.5)*255 for v in floor_normal]
        assert max(abs(a-b) for a,b in zip(normals.getpixel(pixel),expected_normal))<3,(name,pixel)
        samples[name]={'ao':ao.getpixel(pixel)[0],'contact':contact.getpixel(pixel)[0]}
    assert samples['foot']['ao']<235,samples
    assert samples['sun_contact']['contact']<160,samples
    assert min(samples['open_floor'].values())>245,samples
    return samples

def cutout_depth_samples(depth):
    project,_=projection((5,3.8,7),(2,1.1,3),58,depth)
    samples=[]
    for x in (1.05,1.35,1.65):
        values=[]
        for point in ((x,2.21,2.25),(x+.15,2.21,2.4)):
            pixel,z=project(point)
            value=depth.getpixel(pixel)[0]
            expected=255*math.log2(1+z)/math.log2(501)
            values.append((value,expected))
        assert values[0][0]>values[0][1]+2,values # hole sees through the panel
        assert abs(values[1][0]-values[1][1])<2,values # solid cell writes its own depth
        samples.append(values)
    return samples

def main():
    output=ROOT/'captures/rendering/occlusion-validation';output.mkdir(parents=True,exist_ok=True)
    project=editor.open_project(ROOT,start_if_needed=False)
    game=project.build_and_run(timeout=180);report={}
    def cmd(name,data=None): return game.command(name,data or {})['result']
    def configure(**values):
        cmd('renderer.configure',values)
        engine.wait_until(lambda:all(cmd('renderer.snapshot')['settings'][k]==v for k,v in values.items()),timeout=5)
        game.wait_frames(36)
    def shot(name):
        result=cmd('capture.shot',{'name':name});game.wait_frames(35);return result
    def save(name):
        path=output/(name+'.png');shutil.copyfile(game.screenshot(after_frames=3).path,path)
        return Image.open(path).convert('RGB')
    def resize(w,h):
        game.resize(w,h);game.wait_frames(35);s=cmd('renderer.snapshot')
        game.resize(round(w*w/s['width']),round(h*h/s['height']))
        engine.wait_until(lambda:(cmd('renderer.snapshot')['width'],cmd('renderer.snapshot')['height'])==(w,h),timeout=8)
    try:
        engine.wait_until(lambda:cmd('world.snapshot')['ready'],timeout=45)
        engine.wait_until(lambda:cmd('renderer.snapshot')['ready'],timeout=60)
        resize(1280,720)
        initial=cmd('renderer.snapshot');assert initial['target_count']==16
        assert initial['prepass_draw_passes']==3 and initial['occlusion_draw_passes']==2
        for name in ('street','interior','laboratory','contact_furniture','contact_corner','shadow_cutout'):
            shot(name);enabled=save(name)
            configure(ambient_occlusion=False);no_ao=save(name+'-no-ao')
            ao_delta=difference(enabled,no_ao);assert ao_delta>.005,(name,ao_delta)
            configure(ambient_occlusion=True,contact_shadows=False);no_contact=save(name+'-no-contact')
            contact_delta=difference(enabled,no_contact)
            configure(contact_shadows=True);assert ImageChops.difference(enabled,save(name+'-restored')).getbbox() is None
            buffers={}
            for view in ('depth','geometry_normals','ao','contact','occlusion_raw'):
                configure(view=view);buffers[view]=save(name+'-'+view)
            metrics=validate_buffers(buffers['depth'],buffers['geometry_normals'],buffers['ao'],buffers['contact'])
            if name=='contact_furniture': metrics['projected_samples']=fixture_samples(buffers['depth'],buffers['geometry_normals'],buffers['ao'],buffers['contact'])
            if name=='shadow_cutout': metrics['projected_cutouts']=cutout_depth_samples(buffers['depth'])
            report[name]={'ao_difference':ao_delta,'contact_difference':contact_delta,**metrics}
            print('PASS',name,report[name],flush=True)
        shot('contact_furniture');configure(view='ao');ao=save('ao-before-return')
        configure(ambient_occlusion=False);assert save('ao-disabled').getextrema()==((255,255),)*3
        configure(view='contact',contact_shadows=False);assert save('contact-disabled').getextrema()==((255,255),)*3
        assert cmd('renderer.snapshot')['prepass_draw_passes']==1 # diagnostics still need geometry
        configure(view='scene',temporal_aa=False);assert cmd('renderer.snapshot')['prepass_draw_passes']==0
        shot('interior');shot('contact_furniture');configure(view='ao')
        assert ImageChops.difference(ao,save('ao-camera-return')).getbbox() is None
        resize(800,502);save('ao-resized')
        s=cmd('renderer.snapshot');assert s['occlusion_width']==400 and s['occlusion_height']==251
        resize(1280,720)
        assert ImageChops.difference(ao,save('ao-resize-return')).getbbox() is None
        for frame in (0,1,2,3,4,30,60,90,120):
            cmd('capture.frame',{'frame':frame});game.wait_frames(4);save('ao-motion-'+str(frame))
        cmd('capture.frame',{'frame':0});game.wait_frames(4)
        assert ImageChops.difference(ao,save('ao-motion-return')).getbbox() is None
        # Current bone palette must reach prepass, including death animation.
        cmd('capture.end');cmd('ai.configure',{'enabled':False});cmd('world.view',{'name':'street'})
        cmd('ai.reset',{'position':{'x':1,'y':.004,'z':4},'yaw':0})
        configure(view='depth');standing=save('soldier-standing-depth')
        cmd('gameplay.damage',{'target':'enemy_1','amount':1000,'source':'player'})
        engine.wait_until(lambda:cmd('ai.snapshot')['actors'][0]['death']>=1,timeout=5)
        collapsed=save('soldier-collapsed-depth')
        changed=sum(ImageChops.difference(standing,collapsed).getchannel('R').histogram()[2:])
        assert changed>30,changed
        report['animated_depth_pixels']=changed
        # Frozen same-camera A/B CPU scopes and submitted draws, no GPU claim.
        shot('street');costs={}
        for label,enabled in (('enabled',True),('disabled',False)):
            configure(view='scene',ambient_occlusion=enabled,contact_shadows=enabled)
            sample=game.profiler.capture(frames=90,warmup_frames=15,timeout=20)
            costs[label]={'renderer':cmd('renderer.snapshot'),'scopes':[asdict(v) for v in sample.scopes()[:16]],
                          'counters':[asdict(v) for v in sample.counters()]}
        report['costs']=costs
        assert cmd('renderer.snapshot')['bake_draws']==initial['bake_draws']
        cmd('capture.end')
    finally:
        (output/'report.json').write_text(json.dumps(report,indent=2)+'\n')
        game.close_engine();game.close()
    errors=[line for line in project.console.read().lines if 'ERROR:' in line]
    assert not errors,'\n'.join(errors)
    print('PASS occlusion buffers, toggles, returns, animation, costs and clean shutdown',flush=True)

if __name__=='__main__':main()
