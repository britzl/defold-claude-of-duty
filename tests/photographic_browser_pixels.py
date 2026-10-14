"""Pixel and quality-cost gates for the photographic WebGL fixture."""
import argparse,json,statistics
from pathlib import Path
from PIL import Image,ImageChops,ImageStat

def main(output):
    report=json.loads((output/'report.json').read_text());results={}
    def image(name):return Image.open(output/(name+'.png')).convert('RGB')
    for name,option in [('street','grade_strength'),('street','vignette'),('street','grain'),('detail','sharpen'),('rifle_ads','ads_dof'),('weapon_fire','bloom_strength')]:
        difference=sum(ImageStat.Stat(ImageChops.difference(image(name),image(name+'_'+option+'_off'))).mean)/3
        assert difference>.0001,(name,option,difference)
        results[name+'/'+option]=difference
    assert ImageChops.difference(image('street'),image('street_return')).getbbox() is None
    assert max(ImageStat.Stat(image('bloom_diagnostic')).mean)>1
    for name in ['street','interior','night']:
        im=image(name+'_exposure');r,g,_=im.getpixel((im.width//2,im.height//2))
        value=2**(r/255*4-2);target=2**(g/255*4-2)
        low,high=report['shots'][name+'_exposure']['renderer']['exposure_limits']
        assert low-.02<=value<=high+.02 and abs(value-target)<.03,(name,value,target)
    for tier in ['low','medium','high']:
        samples=sorted(s['ms'] for s in report['gpu']['samples'] if (s.get('label') or '').startswith('photo_cost_'+tier))
        stats=report['shots']['photo_cost_'+tier+'_1']['renderer']
        results[tier]={'samples':len(samples),'median_gpu_ms':statistics.median(samples) if samples else None,
            'p95_gpu_ms':samples[int(len(samples)*.95)] if samples else None,'target_bytes':stats['target_bytes']}
        assert stats['lens_draw_passes']==(0 if tier=='low' else 2)
    assert results['low']['target_bytes']<results['medium']['target_bytes']<results['high']['target_bytes']
    results['street_exact_repeat']=True
    (output/'pixel-validation.json').write_text(json.dumps(results,indent=2)+'\n')
    print('PASS photographic WebGL pixels, repeats, bounded exposure and quality tiers')
if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=Path('captures/rendering/photographic-browser'))
    main(parser.parse_args().output)
