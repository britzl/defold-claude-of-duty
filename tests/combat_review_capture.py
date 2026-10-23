"""Record the shared combat replay in an owned native debug engine.
Use tools/capture_combat_review.mjs for the release-browser replay. Neither
recording is a performance benchmark; use sustained_profile.py separately.
"""
import argparse,hashlib,json,os,re,shutil,socket,subprocess,time
from pathlib import Path
from automation_bridge import editor,engine
ROOT=Path(__file__).resolve().parents[1]
def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--window-video',action='store_true',help='Use the optional platform recorder instead of framebuffer samples')
    args=p.parse_args()
    out=args.output.resolve();out.mkdir(parents=True,exist_ok=True)
    project=editor.open_project(ROOT,start_if_needed=False);project.compile(timeout=180)
    with socket.socket() as s:s.bind(('127.0.0.1',0));port=s.getsockname()[1]
    report={'phases':[],'errors':[],'method':'Native debug replay; recording overhead included; not a benchmark'}
    digest=hashlib.sha256()
    for folder in ('game','main','render','world','weapons','soldiers'):
        for path in sorted((ROOT/folder).rglob('*')):
            if path.is_file():digest.update(str(path.relative_to(ROOT)).encode());digest.update(path.read_bytes())
    report['source_sha256']=digest.hexdigest()
    log_path=out/'engine.log'
    with log_path.open('w') as log:
        process=subprocess.Popen([str(ROOT/'build/arm64-osx/dmengine'),str(ROOT/'build/default/game.projectc'),
            '--config=combat_review.enabled=1','--config=display.width=640','--config=display.height=360',
            '--config=display.high_dpi=0',f'--config=profiler.remotery_port={port}'],cwd=ROOT,
            stdout=log,stderr=subprocess.STDOUT,env={**os.environ,'DM_SERVICE_PORT':'dynamic'})
        game=None;recording=None;seen=0;frames=[];last_frame=0
        try:
            def service():
                assert process.poll() is None,log_path.read_text()
                m=re.search(r'Engine service started on port (\d+)',log_path.read_text())
                return int(m[1]) if m else None
            game=engine.connect(engine.wait_until(service,timeout=30))
            def poll():
                nonlocal seen,recording,last_frame
                lines=log_path.read_text().splitlines()
                for line in lines[seen:]:
                    if 'ERROR:' in line:report['errors'].append(line)
                    m=re.search(r'COMBAT_REVIEW (READY|PHASE|PASS) (.*)',line)
                    if not m:continue
                    kind,data=m[1],json.loads(m[2]);print(kind,data.get('name',''),flush=True)
                    if kind=='READY':
                        assert (data['width'],data['height'])==(1280,720),'Wrong framebuffer size'
                        report['ready']=data
                        if args.window_video:
                            report['recording_capabilities']=vars(game.video_recording.capabilities())
                            recording=game.video_recording.start(out/'combat.mp4',size=(1280,720),fps=30,audio=False)
                        else:
                            report['method']='Native debug framebuffer screenshots, sampled at up to 10 Hz; not a performance or full-rate temporal-quality measurement'
                            (out/'frames').mkdir(exist_ok=True)
                        report['capture_start']=time.time();game.command('combat_review.start',{})
                    elif kind=='PHASE':report['phases'].append(data)
                    else:report['result']=data
                seen=len(lines)
                if 'capture_start' in report and not recording and time.monotonic()-last_frame>=.1:
                    path=out/'frames'/('%05d.png'%len(frames))
                    shutil.copyfile(game.screenshot().path,path)
                    frames.append({'file':str(path),'wall':time.time()});last_frame=time.monotonic()
                assert process.poll() is None,log_path.read_text()
                assert not report['errors'],report['errors']
                return report.get('result')
            engine.wait_until(poll,timeout=240,interval=.05)
        finally:
            if recording:report['recording']=recording.stop().to_dict()
            report['frames']=frames
            if game:game.close_engine();game.close()
            if process.poll() is None:process.terminate()
            process.wait(timeout=15)
            (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    if frames:
        lines=[]
        for i,f in enumerate(frames):
            lines.append("file '"+f['file'].replace("'","'\\''")+"'")
            if i+1<len(frames):lines.append('duration '+str(frames[i+1]['wall']-f['wall']))
        (out/'frames.txt').write_text('\n'.join(lines)+'\n')
        subprocess.run(['ffmpeg','-v','error','-y','-f','concat','-safe','0','-i',str(out/'frames.txt'),
            '-fps_mode','vfr','-pix_fmt','yuv420p',str(out/'combat.mp4')],check=True)
if __name__=='__main__':main()
