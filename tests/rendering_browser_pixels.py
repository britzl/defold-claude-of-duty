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
    for first,second in [('rifle_hip','rifle_materials_off'),('weapon_indoor','weapon_indoor_ungated'),
                         ('weapon_fire','weapon_flash_off'),('combat_effects','combat_effects_off'),
                         ('combat_effects','combat_soft_off'),('combat_effects','combat_decals_off'),('combat_glass','combat_glass_off')]:
        a=Image.open(output/(first+'.png')).convert('RGB');b=Image.open(output/(second+'.png')).convert('RGB')
        difference=sum(ImageStat.Stat(ImageChops.difference(a,b)).mean)/3
        assert difference>.002,(first,second,difference);metrics[first+'_'+second]=difference
    assert ImageChops.difference(Image.open(output/'combat_effects.png'),Image.open(output/'combat_effects_return.png')).getbbox() is None
    for first,second in [('street','sunset'),('sunset','night'),('sky_daylight','clouds_disabled'),
                         ('sunset','sunset_fog_disabled'),('shafts_shadowed','shafts_unshadowed'),
                         ('environment_atlas','sunset_environment'),('sunset_environment','night_environment')]:
        a=Image.open(output/(first+'.png')).convert('RGB');b=Image.open(output/(second+'.png')).convert('RGB')
        difference=sum(ImageStat.Stat(ImageChops.difference(a,b)).mean)/3
        assert difference>.1,(first,second,difference);metrics[first+'_'+second]=difference
    for first,second in [('sky_daylight','clouds_return'),('shafts_shadowed','shafts_return')]:
        assert ImageChops.difference(Image.open(output/(first+'.png')),Image.open(output/(second+'.png'))).getbbox() is None
    for name in ('reflections','glass','local_lights'):
        enabled=Image.open(output/(name+'.png')).convert('RGB')
        disabled=Image.open(output/(name+'_disabled.png')).convert('RGB')
        difference=sum(ImageStat.Stat(ImageChops.difference(enabled,disabled)).mean)/3
        assert difference>.01,(name,difference);metrics[name]=difference
    mask=Image.open(output/'reflection_confidence.png').convert('RGB')
    assert sum(r>20 for r,g,b in mask.getdata())>100
    assert ImageChops.difference(Image.open(output/'glass.png'),Image.open(output/'glass_return.png')).getbbox() is None

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
    if 'temporal_motion' in report['shots']:
        def opened(name): return Image.open(output/(name+'.png')).convert('RGB')
        for a,b in [('street','temporal_disabled'),('shadow_cutout','cutout_temporal_disabled'),
                    ('weapon','weapon_aa_disabled'),('ads','ads_aa_disabled')]:
            difference=sum(ImageStat.Stat(ImageChops.difference(opened(a),opened(b))).mean)/3
            assert difference>.005,(a,b,difference);metrics[b]=difference
        motion=opened('temporal_motion')
        pixels=list(motion.getdata())
        bad=sum(abs(r-128)>2 or abs(g-128)>2 for r,g,b in pixels)
        assert bad/len(pixels)<.025,(bad,len(pixels))
        history_mean=ImageStat.Stat(opened('temporal_history')).mean[0]
        assert history_mean>70,history_mean
        moving=sum(abs(r-128)>3 or abs(g-128)>3 for r,g,b in opened('temporal_camera_motion').getdata())
        assert moving>1000,moving
        metrics['temporal']={'static_velocity_bad_fraction':bad/len(pixels),'history_weight_mean':history_mean/255,
            'camera_motion_pixels':moving}
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
