"""Pixel gates for the focused WebGL material catalogue fixture."""
import argparse
import json
import math
from pathlib import Path
from PIL import Image, ImageChops, ImageStat
from catalogue_smoke import leaf_fraction, delta, SHOTS
from materials_smoke import atlas_layout, validate_maps


def main(output):
    report=json.loads((output/'report.json').read_text())
    assert not report['errors'] and report['result']['renderer']['surface_count']==19
    stats=report['result']['renderer'];width,height=stats['atlas_width'],stats['atlas_height']
    quality=stats['material_quality'];maps={}
    for view in ('albedo','normals','material','coverage'):
        combined=Image.new('RGB',(width,height))
        for row in range(math.ceil(height/1024)):
            for column in range(math.ceil(width/1024)):
                page=row*math.ceil(width/1024)+column+1
                image=Image.open(output/f'{view}_page_{page}.png').convert('RGB')
                assert image.size==(1024,1024)
                combined.paste(image,(column*1024,height-(row+1)*1024))
        maps[view]=combined;combined.save(output/(view+'.png'))
    validate_maps({k:v for k,v in maps.items() if k!='coverage'},atlas_layout(quality))
    def image(name): return Image.open(output/(name+'.png')).convert('RGB')
    metrics={'coverage':{},'shadows':{},'motion':{}}
    for name in SHOTS: assert name in report['shots']
    for name,distance in [('material_foliage',2.32),('material_foliage_far',25.32),('foliage_back',2.32)]:
        normals=image(name+'_geometry_normals');depth=image(name+'_depth')
        metrics['coverage'][name]=leaf_fraction(normals,distance)
        assert all((d==(255,255,255))==(n==(0,0,0)) for d,n in zip(depth.getdata(),normals.getdata()))
    assert abs(metrics['coverage']['material_foliage']-metrics['coverage']['foliage_back'])<.025
    assert abs(metrics['coverage']['material_foliage']-metrics['coverage']['material_foliage_far'])<.13
    for name in ('foliage_shadow','foliage_local'):
        enabled=image(name);disabled=image(name+'_disabled');restored=image(name+'_restored')
        difference=delta(enabled,disabled);assert difference>.005,(name,difference)
        assert delta(enabled,restored)==0,(name,'shadow restore')
        metrics['shadows'][name]=difference
    assert delta(image('material_foliage'),image('material_foliage_return'))==0
    for name in ('sand','corrugated','burlap','foliage'):
        motion=image('material_'+name+'_motion')
        moving=sum(abs(r-128)>3 or abs(g-128)>3 for r,g,b in motion.getdata())
        assert moving>1000,(name,moving)
        metrics['motion'][name]=moving
    mask=maps['coverage'];means=[]
    for name,level,x,y,size in atlas_layout(quality):
        if name=='foliage':
            core=mask.crop((x+1,height-y-size-1,x+size+1,height-y-1))
            mean=ImageStat.Stat(core).mean[0]/255;means.append(mean)
            if level==0: assert .05<mean<.5 and core.getextrema()[0]==(0,255)
    assert max(means)-min(means)<.025,means
    metrics['mask_mip_means']=means
    (output/'pixel-report.json').write_text(json.dumps(metrics,indent=2)+'\n')
    print('PASS WebGL catalogue maps, foliage coverage/depth, shadows, motion and exact camera return')


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,default=Path('build/material-catalogue-browser-validation'))
    main(parser.parse_args().output)
