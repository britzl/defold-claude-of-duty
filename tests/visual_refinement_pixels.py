"""Check feature effects and exact returns from the visual_refinement browser suite."""
import argparse
import json
from pathlib import Path
from PIL import Image, ImageChops, ImageStat

ROOT=Path(__file__).resolve().parents[1]


def main(output):
    report=json.loads((output/'report.json').read_text())
    assert not report['errors'],report['errors']
    def opened(name): return Image.open(output/(name+'.png')).convert('RGB')
    metrics={}
    for name in ('weathering_facade','material_grazing','sky_daylight','foliage_shadow','micro_detail','parallax_tile'):
        enabled=opened(name)
        delta=sum(ImageStat.Stat(ImageChops.difference(enabled,opened(name+'_disabled'))).mean)/3
        assert delta>.01,(name,delta)
        assert ImageChops.difference(enabled,opened(name+'_return')).getbbox() is None,name
        metrics[name]={'mean_pixel_change':delta,'exact_return':True}
    assert ImageChops.difference(opened('street'),opened('street_return')).getbbox() is None
    metrics['street']={'exact_return':True}
    (output/'pixel-validation.json').write_text(json.dumps(metrics,indent=2)+'\n')
    print('PASS feature toggles and seven exact image returns',metrics)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=ROOT/'build/visual-refinement-browser-render')
    main(parser.parse_args().output)
