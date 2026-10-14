"""Step-5 GPU gates on the production Metal renderer and existing capture cameras.

PYTHONPATH=automation-bridge-python python3 tests/lighting_smoke.py
Writes unmodified screenshots, A/B differences and resource measurements.
"""
import json
import shutil
from pathlib import Path
from PIL import Image, ImageChops, ImageStat
from automation_bridge import editor, engine

ROOT = Path(__file__).resolve().parents[1]


def environment_seams(image):
    """Approach all 12 cube edges through both adjacent faces and bilinear gutters."""
    from itertools import combinations, product
    from math import floor
    def sample(d, row):
        x,y,z=d;a=list(map(abs,d))
        if a[0]>=a[1] and a[0]>=a[2]: face=0 if x>0 else 1;p=((-z if x>0 else z)/a[0],-y/a[0])
        elif a[1]>=a[2]: face=2 if y>0 else 3;p=(x/a[1],(z if y>0 else -z)/a[1])
        else: face=4 if z>0 else 5;p=((x if z>0 else -x)/a[2],-y/a[2])
        u=face*66+.5+(p[0]*.5+.5)*64
        v=image.height-1-(row*66+.5+(p[1]*.5+.5)*64)
        ix,iy=floor(u),floor(v);fx,fy=u-ix,v-iy
        return [sum(image.getpixel((ix+dx,iy+dy))[c]*(fx if dx else 1-fx)*(fy if dy else 1-fy)
                    for dx,dy in product((0,1),repeat=2)) for c in range(3)]
    maximum=0.0
    for first,second in combinations(range(3),2):
        third=3-first-second
        for sign_a,sign_b in product((-1,1),repeat=2):
            for along in (-.8,-.3,.3,.8):
                d=[0.0]*3;d[first]=sign_a;d[second]=sign_b;d[third]=along
                a=d.copy();b=d.copy();a[first]*=1.00001;b[second]*=1.00001
                for row in range(1,8):
                    maximum=max(maximum,max(abs(x-y) for x,y in zip(sample(a,row),sample(b,row))))
    assert maximum<3,maximum
    return maximum


def main():
    output = ROOT / 'captures/rendering/lighting-validation'
    output.mkdir(parents=True, exist_ok=True)
    project = editor.open_project(ROOT, start_if_needed=False)
    game = project.build_and_run(timeout=180)
    report = {}

    def cmd(name, data=None):
        return game.command(name, data or {})['result']

    def configure(**changes):
        cmd('renderer.configure', changes)
        engine.wait_until(lambda: all(cmd('renderer.snapshot')['settings'][k] == v for k, v in changes.items()), timeout=5)
        game.wait_frames(4)

    def save(name):
        path = output / (name + '.png')
        shutil.copyfile(game.screenshot(after_frames=3).path, path)
        return Image.open(path).convert('RGB')

    def delta(a, b):
        return sum(ImageStat.Stat(ImageChops.difference(a, b)).mean) / 3

    def shot(name):
        cmd('capture.shot', {'name': name})
        game.wait_frames(35)

    def resize(w, h):
        game.resize(w, h)
        game.wait_frames(35)
        stats = cmd('renderer.snapshot')
        game.resize(round(w*w/stats['width']), round(h*h/stats['height']))
        engine.wait_until(lambda: (cmd('renderer.snapshot')['width'], cmd('renderer.snapshot')['height']) == (w, h), timeout=5)

    try:
        engine.wait_until(lambda: cmd('world.snapshot')['ready'], timeout=45)
        engine.wait_until(lambda: cmd('renderer.snapshot')['ready'], timeout=20)
        resize(1280, 720)
        initial = cmd('renderer.snapshot')
        assert initial['volume_count'] == 4 and initial['reflection_levels'] == 6
        assert initial['target_count'] == 12
        shot('interior')
        default = save('interior')
        configure(interior_lighting=False)
        ungated = save('interior-ungated')
        assert delta(default, ungated) > 3
        # The open doorway is exterior geometry/sky, so volume gating must not
        # darken it along with the room. This ROI lies wholly above the threshold.
        doorway = (585, 325, 690, 395)
        assert ImageChops.difference(default.crop(doorway), ungated.crop(doorway)).getbbox() is None
        configure(interior_lighting=True)
        assert ImageChops.difference(default, save('interior-restored')).getbbox() is None
        configure(local_lights=False, fog=False)
        gated = save('interior-sky-only')
        configure(interior_lighting=False)
        full_sky = save('interior-full-sky')
        room = (100, 250, 490, 440)
        gated_mean = sum(ImageStat.Stat(gated.crop(room)).mean)/3
        full_mean = sum(ImageStat.Stat(full_sky.crop(room)).mean)/3
        assert full_mean > gated_mean + 15, (gated_mean, full_mean)
        report['interior'] = {'toggle_mean_difference': delta(default, ungated),
            'room_sky_gated_mean': gated_mean, 'room_full_sky_mean': full_mean,
            'doorway_unchanged': True, 'exact_restore': True}
        print('PASS interior attenuation, bright doorway and exact restoration', report['interior'], flush=True)

        shot('laboratory')
        lab = save('laboratory')
        configure(interior_lighting=False)
        assert ImageChops.difference(lab, save('laboratory-volume-isolation')).getbbox() is None
        configure(environment_filter=False)
        sharp = save('laboratory-unfiltered')
        assert delta(lab, sharp) > .03
        configure(environment_filter=True)
        assert ImageChops.difference(lab, save('laboratory-filter-restored')).getbbox() is None
        report['reflection_filter'] = {'mean_difference': delta(lab, sharp), 'exact_restore': True}
        print('PASS roughness filter contribution and laboratory volume isolation', report['reflection_filter'], flush=True)

        # Inspect every face/roughness and the linear BRDF lookup at 1:1 pixels.
        resize(initial['environment_width'], initial['environment_height'])
        configure(view='environment_atlas', bloom=False)
        atlas = save('environment-atlas')
        width, height = atlas.size
        size, stride = 64, 66
        assert (width, height) == (396, 594)
        def tile(face, row):
            return atlas.crop((face*stride+1, height-(row*stride+1+size), face*stride+1+size, height-(row*stride+1)))
        # At roughness 0 and normal incidence, the integrated BRDF is F0.
        lut = tile(0, 8)
        assert all(abs(a-b) <= 2 for a,b in zip(lut.getpixel((63,63)), (255,0,0)))
        assert 55 < lut.getpixel((63,0))[0] < 100, lut.getpixel((63,0))
        assert lut.getpixel((3,63))[1] > 180
        for face in range(1, 6):
            assert ImageChops.difference(lut, tile(face, 8)).getbbox() is None
        spreads=[]
        for row in range(1, 7):
            samples=[tile(face,row) for face in range(6)]
            strip=Image.new('RGB',(384,64))
            for face,t in enumerate(samples): strip.paste(t,(face*64,0))
            spreads.append(sum(ImageStat.Stat(strip).stddev)/3)
        assert spreads[-1] < spreads[0]*.8, spreads
        assert all(v > 2 for v in spreads), spreads
        report['environment']={'maximum_seam_difference':environment_seams(atlas),'roughness_spreads':spreads,'brdf_normal_smooth':lut.getpixel((63,63)),
            'brdf_normal_rough':lut.getpixel((63,0)),'dimensions':atlas.size}
        print('PASS GGX roughness levels and integrated BRDF endpoints', report['environment'], flush=True)
        resize(1280,720)
        shot('street')
        before=save('street')
        shot('interior')
        shot('street')
        assert ImageChops.difference(before,save('street-return')).getbbox() is None
        final=cmd('renderer.snapshot')
        assert initial['bake_draws']==final['bake_draws'] and final['target_count']==12
        report['renderer']=final
        report['scope']='Frozen production cameras; GPU pixel assertions. CPU/draw profiles are in the baseline manifests.'
        cmd('capture.end')
    finally:
        (output/'report.json').write_text(json.dumps(report,indent=2)+'\n')
        game.close_engine();game.close()
    errors=[line for line in project.console.read().lines if 'ERROR:' in line]
    assert not errors,'\n'.join(errors)
    print('PASS step-5 lighting, environment, resource reuse and clean shutdown',flush=True)


if __name__ == '__main__':
    main()
