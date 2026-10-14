"""Validate captures from tools/validate_rendering_browser.mjs on the actual GPU."""
import json
from pathlib import Path
from PIL import Image, ImageChops, ImageStat
from materials_smoke import atlas_layout,validate_maps

ROOT=Path(__file__).resolve().parents[1]

def main(output=ROOT/'captures/rendering/browser-validation'):
    report=json.loads((output/'report.json').read_text())
    assert not report['errors'] and report['result']['renderer']['surface_count']==15
    stats=report['result']['renderer'];width,height=stats['atlas_width'],stats['atlas_height']
    images={};columns=(width+1023)//1024
    for view in ('albedo','normals','material'):
        combined=Image.new('RGB',(width,height))
        for row in range((height+1023)//1024):
            for column in range(columns):
                image=Image.open(output/f'{view}_page_{row*columns+column+1}.png').convert('RGB')
                assert image.size==(1024,1024),image.size
                combined.paste(image,(column*1024,height-(row+1)*1024))
        images[view]=combined;combined.save(output/(view+'.png'))
    validate_maps(images,atlas_layout(stats['material_quality']))
    metrics={}
    for name in ('weathering_facade','micro_detail','parallax_tile'):
        enabled=Image.open(output/(name+'.png')).convert('RGB')
        disabled=Image.open(output/(name+'_disabled.png')).convert('RGB')
        delta=sum(ImageStat.Stat(ImageChops.difference(enabled,disabled)).mean)/3
        assert delta>.01,(name,delta);metrics[name]=delta
    for name,other,minimum in [('interior','interior_ungated',3),('laboratory','laboratory_unfiltered',.03)]:
        enabled=Image.open(output/(name+'.png')).convert('RGB')
        disabled=Image.open(output/(other+'.png')).convert('RGB')
        delta=sum(ImageStat.Stat(ImageChops.difference(enabled,disabled)).mean)/3
        assert delta>minimum,(name,delta);metrics[other]=delta
    lab=Image.open(output/'laboratory.png').convert('RGB')
    isolated=Image.open(output/'laboratory_no_volumes.png').convert('RGB')
    assert ImageChops.difference(lab,isolated).getbbox() is None
    assert stats['volume_count']==4 and stats['reflection_levels']==6
    first=Image.open(output/'street.png').convert('RGB')
    returned=Image.open(output/'street_return.png').convert('RGB')
    assert ImageChops.difference(first,returned).getbbox() is None,'Browser return pixels differ'
    if report.get('restored'):
        restored=Image.open(output/'street_restored.png').convert('RGB')
        assert ImageChops.difference(first,restored).getbbox() is None,'Context restoration changed pixels'
    (output/'pixel-validation.json').write_text(json.dumps({'mip_regions':len(atlas_layout()),
        'all_wrapped_borders_valid':True,'exact_street_return':True,'exact_context_restoration':bool(report.get('restored')),'effect_differences':metrics},indent=2)+'\n')
    print('PASS WebGL texture channels, mip chains, feature toggles and exact return pixels',metrics)

if __name__=='__main__':
    import argparse
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=ROOT/'captures/rendering/browser-validation')
    main(parser.parse_args().output)
