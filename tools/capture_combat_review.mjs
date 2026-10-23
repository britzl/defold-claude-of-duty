// Record the shared release-browser visual replay, separately from benchmarks.
import {createRequire} from 'node:module';
import {createServer} from 'node:http';
import {createHash} from 'node:crypto';
import {readFile,writeFile,mkdir,rename} from 'node:fs/promises';
import {resolve,join,extname,sep} from 'node:path';
const args=Object.fromEntries(process.argv.slice(2).map(s=>s.slice(2).split(/=(.*)/s).slice(0,2)));
if(!args.bundle||!args.output)throw Error('Supply --bundle and --output');
const root=resolve(args.bundle),out=resolve(args.output);
await mkdir(out,{recursive:true});
const types={'.wasm':'application/wasm','.js':'application/javascript','.html':'text/html'};
const server=createServer(async(req,res)=>{
  try {const path=resolve(root,'.'+(req.url==='/'?'/index.html':req.url));
    if(!path.startsWith(root+sep)){res.writeHead(403);res.end();return;}
    const bytes=await readFile(path);
    res.writeHead(200,{'Content-Type':types[extname(path)]??'application/octet-stream'});res.end(bytes);
  }catch{res.writeHead(404);res.end();}
});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const {chromium}=createRequire(import.meta.url)(process.env.PLAYWRIGHT_MODULE??'playwright');
let browser,context,video;
const report={phases:[],errors:[],method:'Release WebGL replay with video capture overhead; not a benchmark'};
report.bundle_sha256={};
for(const name of ['ClaudeofDuty.wasm','archive/game0.arcd','archive/game0.dmanifest'])
  report.bundle_sha256[name]=createHash('sha256').update(await readFile(join(root,name))).digest('hex');
try {
  browser=await chromium.launch({headless:true,executablePath:args.browser,args:['--use-angle=metal','--ignore-gpu-blocklist','--force-color-profile=srgb','--mute-audio']});
  report.browser=browser.version();
  context=await browser.newContext({viewport:{width:1280,height:762},deviceScaleFactor:1,recordVideo:{dir:out,size:{width:1280,height:762}}});
  const page=await context.newPage();video=page.video();
  page.on('pageerror',e=>report.errors.push(e.message));
  page.on('console',m=>{
    const text=m.text();if(text.includes('ERROR:')||/GL_INVALID_|GL_OUT_OF_MEMORY|WebGL:.*error/i.test(text))report.errors.push(text);
    const match=text.match(/COMBAT_REVIEW (READY|PHASE|PASS) (.*)/);if(!match)return;
    const data=JSON.parse(match[2]);console.log(match[1],data.name??'');
    if(match[1]==='READY'){report.ready=data;report.capture_start=Date.now()/1000;page.evaluate(()=>window.__COMBAT_REVIEW_START__=true).catch(e=>report.errors.push(String(e)));}
    else if(match[1]==='PHASE')report.phases.push(data);else report.result=data;
  });
  await page.goto('http://127.0.0.1:'+server.address().port,{timeout:120000});
  const deadline=Date.now()+240000;
  while(!report.result&&Date.now()<deadline){if(report.errors.length)throw Error(report.errors.join('\n'));await new Promise(r=>setTimeout(r,250));}
  if(!report.result)throw Error('Replay timeout');
  if(report.ready.width!==1280||report.ready.height!==720)throw Error('Wrong framebuffer size');
  if(report.ready.engine.is_debug)throw Error('Expected release browser');
} finally {
  if(context)await context.close();if(video)await rename(await video.path(),join(out,'combat.webm'));
  if(browser)await browser.close();await new Promise(r=>server.close(r));
  await writeFile(join(out,'report.json'),JSON.stringify(report,null,2)+'\n');
}
