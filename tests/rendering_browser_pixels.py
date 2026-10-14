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
    if stats.get('shadow_cascades')==4:
        assert stats['shadow_atlas_size']==2048 and stats['shadow_draw_passes']==4
        for name in ('shadow_distance','shadow_cutout','shadow_remote'):
            enabled=Image.open(output/(name+'.png')).convert('RGB')
            disabled=Image.open(output/(name+'_disabled.png')).convert('RGB')
            difference=sum(ImageStat.Stat(ImageChops.difference(enabled,disabled)).mean)/3
            assert difference>.05,(name,difference);metrics[name]=difference
        from shadows_smoke import cutout_samples
        metrics['cutout_coverage']=cutout_samples(Image.open(output/'shadow_cutout_visibility.png').convert('RGB'))
        remote=Image.open(output/'shadow_remote.png').convert('RGB')
        returned=Image.open(output/'shadow_remote_return.png').convert('RGB')
        assert ImageChops.difference(remote,returned).getbbox() is None
        atlas=Image.open(output/'shadow_atlas.png').convert('RGB');w,h=atlas.size
        for y in (0,h//2):
            for x in (0,w//2):
                assert sum(atlas.crop((x,y,x+w//2,y+h//2)).getchannel('R').histogram()[:250])>100
    from occlusion_smoke import validate_buffers,fixture_samples,cutout_depth_samples
    for name in ('street','contact_furniture','contact_corner','shadow_cutout'):
        buffers=[Image.open(output/(name+'_'+view+'.png')).convert('RGB') for view in ('depth','geometry_normals','ao','contact')]
        metrics[name+'_buffers']=validate_buffers(*buffers)
        if name=='contact_furniture': metrics['projected_contacts']=fixture_samples(*buffers)
        if name=='shadow_cutout': metrics['projected_cutout_depth']=cutout_depth_samples(buffers[0])
    furniture=Image.open(output/'contact_furniture.png').convert('RGB')
    for suffix in ('no_ao','no_contact','disabled'):
        other=Image.open(output/('contact_furniture_'+suffix+'.png')).convert('RGB')
        delta=sum(ImageStat.Stat(ImageChops.difference(furniture,other)).mean)/3
        assert delta>.005,(suffix,delta);metrics[suffix]=delta
    assert ImageChops.difference(furniture,Image.open(output/'contact_furniture_return.png').convert('RGB')).getbbox() is None
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
