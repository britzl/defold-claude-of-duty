"""Qualify low/high GPU maps using owned processes and launch-only settings.

Requires a current native editor build. Never changes editor preferences.
"""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time
from PIL import Image
from automation_bridge import engine
from materials_smoke import atlas_layout,atlas_stats,validate_maps

ROOT=Path(__file__).resolve().parents[1]

def main():
    output=ROOT/'captures/rendering/preset-validation';output.mkdir(parents=True,exist_ok=True)
    report={}
    for quality in ('low','high'):
        folder=output/quality;folder.mkdir(exist_ok=True)
        with (folder/'engine.log').open('w') as log:
            process=subprocess.Popen([str(ROOT/'build/arm64-osx/dmengine'),str(ROOT/'build/default/game.projectc'),
                '--config=render.material_quality='+quality,'--config=display.width=1024','--config=display.height=1024',
                '--config=display.high_dpi=0'],cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,
                env={**os.environ,'DM_SERVICE_PORT':'dynamic'})
            game=None
            try:
                def ready_port():
                    assert process.poll() is None,(folder/'engine.log').read_text()
                    match=re.search(r'Engine service started on port (\d+)',(folder/'engine.log').read_text())
                    return int(match[1]) if match else None
                port=engine.wait_until(ready_port,timeout=20)
                game=engine.connect(port,timeout=30)
                def cmd(name,data=None): return game.command(name,data or {})['result']
                engine.wait_until(lambda: cmd('world.snapshot')['ready'],timeout=45)
                engine.wait_until(lambda: cmd('renderer.snapshot')['ready'],timeout=90)
                cmd('capture.shot',{'name':'laboratory'});game.wait_frames(35)
                game.resize(1024,1024);game.wait_frames(35)
                size=cmd('renderer.snapshot')
                game.resize(round(1024**2/size['width']),round(1024**2/size['height']))
                engine.wait_until(lambda: (cmd('renderer.snapshot')['width'],cmd('renderer.snapshot')['height'])==(1024,1024),timeout=10)
                stats=cmd('renderer.snapshot');expected=atlas_stats(quality)
                assert stats['material_quality']==quality and stats['bake_draws']==expected['draws']
                assert stats['target_count']==23 and stats['width']==1024 and stats['height']==1024,stats
                width,height=stats['atlas_width'],stats['atlas_height'];columns=(width+1023)//1024
                maps={}
                for view in ('albedo','normals','material'):
                    combined=Image.new('RGB',(width,height))
                    for row in range((height+1023)//1024):
                        for column in range(columns):
                            cmd('renderer.configure',{'view':view,'atlas_page':row*columns+column+1})
                            shot=game.screenshot(after_frames=5)
                            image=Image.open(shot.path).convert('RGB')
                            assert image.size==(1024,1024)
                            combined.paste(image,(column*1024,height-(row+1)*1024))
                    combined.save(folder/(view+'.png'));maps[view]=combined
                validate_maps(maps,atlas_layout(quality))
                cmd('capture.shot',{'name':'street'});game.wait_frames(35)
                shutil.copyfile(game.screenshot().path,folder/'street.png')
                report[quality]=stats
                print('PASS',quality,'GPU atlas, channels, mip borders and owned-resource cleanup',flush=True)
            finally:
                if game: game.close_engine();game.close()
                if process.poll() is None: process.terminate()
                process.wait(timeout=10)
            errors=[line for line in (folder/'engine.log').read_text().splitlines() if 'ERROR:' in line]
            assert not errors,'\n'.join(errors)
    (output/'report.json').write_text(json.dumps(report,indent=2)+'\n')

if __name__=='__main__': main()
