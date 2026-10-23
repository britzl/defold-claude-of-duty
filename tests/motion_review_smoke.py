"""Focused foliage/shadow/effects camera sweeps using continuous TAA history.
Frame-addressed framebuffer samples hold between steps; not a frame-rate test.
"""
import argparse,json,shutil
from pathlib import Path
from PIL import Image,ImageChops,ImageStat
from automation_bridge import editor,engine
ROOT=Path(__file__).resolve().parents[1]
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
 a.output.mkdir(parents=True,exist_ok=True);report={}
 project=editor.open_project(ROOT,start_if_needed=False);game=project.build_and_run(timeout=180,focus=False)
 def cmd(name,data=None):return game.command(name,data or {})['result']
 try:
  engine.wait_until(lambda:cmd('world.snapshot')['ready'] and cmd('renderer.snapshot')['ready'],timeout=90)
  game.resize(640,360);game.wait_frames(20)
  r=cmd('renderer.snapshot');game.resize(round(640*1280/r['width']),round(360*720/r['height']));game.wait_frames(20)
  for name in ('material_foliage_far','shadow_distance','combat_effects'):
   dest=a.output/name;dest.mkdir(exist_ok=True)
   cmd('capture.shot',{'name':name,'temporal_live':True});game.wait_frames(65)
   before=cmd('renderer.snapshot');previous=None;differences=[]
   for frame in range(0,121,2):
    cmd('capture.frame',{'frame':frame});path=dest/('%04d.png'%frame)
    shutil.copyfile(game.screenshot(after_frames=2).path,path)
    im=Image.open(path).convert('RGB')
    if previous:differences.append(sum(ImageStat.Stat(ImageChops.difference(previous,im)).mean)/3)
    previous=im
   after=cmd('renderer.snapshot')
   assert before['temporal_resets']==after['temporal_resets'],name+' reset temporal history'
   assert max(differences)<25,(name,max(differences))
   report[name]={'frames':61,'history_resets':0,'max_frame_difference':max(differences),'differences':differences}
   print('PASS',name,report[name]['max_frame_difference'],flush=True)
 finally:
  game.close_engine();game.close();(a.output/'report.json').write_text(json.dumps(report,indent=2)+'\n')
if __name__=='__main__':main()
