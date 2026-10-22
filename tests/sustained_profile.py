"""Release native wall-frame/RSS workload. No GPU/presentation timing claim.
Bundle with tests/sustained.project, then pass the bundled app executable.
Default: three fresh processes, 60 s warm-up + 300 s sample each, sequential.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time


def main():
    p=argparse.ArgumentParser()
    p.add_argument('--executable',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--runs',type=int,default=3)
    p.add_argument('--warmup',type=float,default=60)
    p.add_argument('--seconds',type=float,default=300)
    p.add_argument('--preset',choices=['auto','low','medium','high','ultra'],default='high')
    p.add_argument('--renderer',type=json.loads,default={},help='JSON renderer overrides for diagnostic cost comparisons')
    p.add_argument('--no-ai',action='store_true',help='Diagnostic only: disable AI behavior; retain skeleton/hitbox updates and change the combat workload')
    p.add_argument('--no-origin-index',action='store_true',help='Diagnostic only: use the previous full collider scan')
    p.add_argument('--window-width',type=int,default=640,help='Logical window pixels; 640 on the target Retina Mac gives 1280 framebuffer pixels')
    p.add_argument('--window-height',type=int,default=360)
    args=p.parse_args()
    if args.runs<1 or args.warmup<0 or args.seconds<=0:p.error('runs and seconds must be positive; warmup must be nonnegative')
    if not isinstance(args.renderer,dict):p.error('renderer must be a JSON object')
    args.output.mkdir(parents=True,exist_ok=True)
    executable=args.executable.resolve()
    reports=[]
    for run in range(1,args.runs+1):
        destination=(args.output/f'run-{run}.json').resolve()
        destination.unlink(missing_ok=True)
        log_path=args.output/f'run-{run}.log'
        rss=[];started=time.monotonic()
        with log_path.open('w') as log:
            process=subprocess.Popen([str(executable),f'--config=sustained.output={destination}',
                f'--config=sustained.warmup={args.warmup}',f'--config=sustained.seconds={args.seconds}',
                f'--config=sustained.preset={args.preset}',f'--config=sustained.renderer={json.dumps(args.renderer,separators=(",",":"))}',
                f'--config=sustained.no_ai={int(args.no_ai)}',f'--config=sustained.no_origin_index={int(args.no_origin_index)}',
                f'--config=display.width={args.window_width}',f'--config=display.height={args.window_height}'],stdout=log,stderr=subprocess.STDOUT,
                cwd=executable.parent,env={**os.environ,'DM_SERVICE_PORT':'dynamic'})
            try:
                deadline=started+args.warmup+args.seconds+150
                while not destination.exists():
                    assert process.poll() is None,log_path.read_text()
                    assert time.monotonic()<deadline,'Benchmark timeout: '+log_path.read_text()
                    result=subprocess.run(['ps','-o','rss=','-p',str(process.pid)],capture_output=True,text=True,check=True)
                    if result.stdout.strip():rss.append({'elapsed':time.monotonic()-started,'rss_mib':int(result.stdout)/1024})
                    time.sleep(1)
                data=json.loads(destination.read_text())
                assert not data['engine']['is_debug'],'Expected release engine'
                assert (data['renderer']['output_width'],data['renderer']['output_height'])==(1280,720),'Wrong framebuffer size'
                data['process_rss_samples']=rss;data['process_peak_rss_mib']=max(x['rss_mib'] for x in rss)
                data['engine_sha256']=hashlib.sha256(executable.read_bytes()).hexdigest()
                resources=executable.parent.parent/'Resources'
                data['bundle_sha256']={name:hashlib.sha256((resources/name).read_bytes()).hexdigest() for name in ['game.projectc','game.arcd','game.dmanifest']}
                data['process_elapsed_seconds']=time.monotonic()-started
                destination.write_text(json.dumps(data,indent=2)+'\n')
                summary={k:data[k] for k in ('frames','process_peak_rss_mib','loaded_seconds','distance','shots','reloads','grenades','kills','restarts','stalls','reached')}
                summary['file']=str(destination);reports.append(summary)
                print('RUN',run,json.dumps(summary),flush=True)
                assert not data.get('failure'),data.get('failure')
            finally:
                if process.poll() is None:process.terminate()
                process.wait(timeout=15)
                (args.output/'summary.json').write_text(json.dumps(reports,indent=2)+'\n')


if __name__=='__main__':main()
