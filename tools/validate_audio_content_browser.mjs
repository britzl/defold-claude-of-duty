// Build with tests/audio_content_browser.project; runs the same scenario as native.
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
import {createServer} from 'node:http';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {resolve,join,extname,sep} from 'node:path';
const args=Object.fromEntries(process.argv.slice(2).map(s=>s.slice(2).split(/=(.*)/s).slice(0,2)));
if(!args.bundle) throw new Error('Supply --bundle=/path/to/HTML5/bundle');
const root=resolve(args.bundle), output=resolve(args.output??'build/audio-content-browser-validation');
await readFile(join(root,'index.html'));
const {chromium}=createRequire(import.meta.url)(process.env.PLAYWRIGHT_MODULE??'playwright');
await mkdir(output,{recursive:true});
const types={'.wasm':'application/wasm','.js':'application/javascript','.html':'text/html','.json':'application/json'};
const server=createServer(async(req,res)=>{
  try {
    const relative=decodeURIComponent(new URL(req.url,'http://localhost').pathname);
    const path=resolve(root,'.'+(relative==='/'?'/index.html':relative));
    if(!path.startsWith(root+sep)) {res.writeHead(403);res.end();return;}
    const bytes=await readFile(path);
    res.writeHead(200,{'Content-Type':types[extname(path)]??'application/octet-stream'});res.end(bytes);
  } catch {res.writeHead(404);res.end();}
});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const report={fixture:{max_time_step:.1,fixed_update_frequency:120},errors:[],checks:[],console:[]};let browser,page;
try {
  report.bundle_sha256={};
  for(const file of ['index.html','ClaudeofDuty.wasm','archive/archive_files.json','archive/game0.arcd'])
    report.bundle_sha256[file]=createHash('sha256').update(await readFile(join(root,file))).digest('hex');
  browser=await chromium.launch({headless:args.headed!=='1',executablePath:args.browser,args:['--autoplay-policy=no-user-gesture-required','--use-angle=metal','--ignore-gpu-blocklist','--force-color-profile=srgb','--mute-audio']});
  page=await browser.newPage({viewport:{width:960,height:682},deviceScaleFactor:1});
  await page.addInitScript(()=>{
    const Native=window.AudioContext||window.webkitAudioContext;
    window.__contentAudio=[];
    const Wrapped=new Proxy(Native,{construct(target,args){
      const context=Reflect.construct(target,args),meter=context.createAnalyser();meter.fftSize=256;
      const record={context,meter,peak:0};window.__contentAudio.push(record);
      const connect=AudioNode.prototype.connect;
      // Observe final engine output without altering its destination connection.
      AudioNode.prototype.connect=function(destination,...rest){
        if(destination===context.destination) connect.call(this,meter);
        return connect.call(this,destination,...rest);
      };
      const values=new Float32Array(256);
      setInterval(()=>{meter.getFloatTimeDomainData(values);for(const value of values) record.peak=Math.max(record.peak,Math.abs(value));},20);
      return context;
    }});
    window.AudioContext=Wrapped;if(window.webkitAudioContext) window.webkitAudioContext=Wrapped;
  });
  let complete=false;
  page.on('pageerror',e=>report.errors.push(e.message));
  page.on('console',message=>{
    const text=message.text();
    if(report.console.length<200) report.console.push(text);
    if(text.includes('ERROR:') || /GL_INVALID_|GL_OUT_OF_MEMORY|WebGL:.*error/i.test(text)) report.errors.push(text);
    const match=text.match(/AUDIO_CONTENT (START|CHECK|PASS) (.*)/);
    if(!match) {console.log(text);return;}
    const data=JSON.parse(match[2]);console.log(match[1],JSON.stringify(data));
    if(match[1]==='START') report.engine=data;
    if(match[1]==='CHECK') report.checks.push(data);
    if(match[1]==='PASS') {report.result=data;complete=true;}
  });
  await page.goto('http://127.0.0.1:'+server.address().port,{timeout:120000,waitUntil:'domcontentloaded'});
  await page.locator('canvas').click({position:{x:20,y:20},timeout:120000});
  await page.evaluate(async()=>{for(const r of window.__contentAudio) await r.context.resume();});
  const deadline=Date.now()+480000;
  while(!complete && Date.now()<deadline){
    await new Promise(r=>setTimeout(r,500));
    if(report.errors.length) throw new Error(report.errors.join('\n'));
  }
  if(!complete) throw new Error('Audio fixture timed out');
  if(report.checks.length!==16) throw new Error('Incomplete audio matrix');
  if(report.errors.length) throw new Error(report.errors.join('\n'));
  report.audio=await page.evaluate(()=>window.__contentAudio.map(r=>({state:r.context.state,peak:r.peak})));
  if(!report.audio.some(r=>r.state==='running' && r.peak>0.0001)) throw new Error('No real Web Audio output after canvas gesture');
  report.webgl=await page.evaluate(()=>{
    const gl=document.querySelector('canvas').getContext('webgl2'), debug=gl.getExtension('WEBGL_debug_renderer_info');
    return {version:gl.getParameter(gl.VERSION),renderer:gl.getParameter(debug?debug.UNMASKED_RENDERER_WEBGL:gl.RENDERER)};
  });
} finally {
  if(page && !report.result) {
    report.page=await page.locator('body').innerText().catch(()=>null);
    await page.screenshot({path:join(output,'failure.png')}).catch(()=>{});
  }
  await writeFile(join(output,'report.json'),JSON.stringify(report,null,2)+'\n');
  if(browser) await browser.close();
  await new Promise(r=>server.close(r));
}
