// Build with tests/rendering_browser.project, then pass --bundle=/path/to/bundle.
// Requires Playwright; PLAYWRIGHT_MODULE may point to an installed module.
import {createRequire} from 'node:module';
import {createServer} from 'node:http';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {resolve,join,extname,sep} from 'node:path';
const args=Object.fromEntries(process.argv.slice(2).map(s=>s.slice(2).split(/=(.*)/s).slice(0,2)));
if(!args.bundle) throw new Error('Supply --bundle=/path/to/HTML5/bundle');
const root=resolve(args.bundle),output=resolve(args.output??'captures/rendering/browser-validation');
const engineArgs=JSON.parse(args['engine-args']??'[]');
if(!Array.isArray(engineArgs) || engineArgs.some(s=>typeof s!=='string')) throw new Error('--engine-args must be a JSON string array');
const require=createRequire(import.meta.url);
const {chromium}=require(process.env.PLAYWRIGHT_MODULE??'playwright');
await mkdir(output,{recursive:true});
const types={'.wasm':'application/wasm','.js':'application/javascript','.html':'text/html','.json':'application/json'};
const server=createServer(async(req,res)=>{
  try {
    const relative=decodeURIComponent(new URL(req.url,'http://localhost').pathname);
    const path=resolve(root,'.'+(relative==='/'?'/index.html':relative));
    if(!path.startsWith(root+sep)) {res.writeHead(403);res.end();return;}
    let bytes=await readFile(path);
    if(path===join(root,'index.html') && engineArgs.length)
      bytes=bytes.toString().replace('EngineLoader.load(',`CUSTOM_PARAMETERS.engine_arguments.push(...${JSON.stringify(engineArgs)});EngineLoader.load(`);
    res.writeHead(200,{'Content-Type':types[extname(path)]??'application/octet-stream'});res.end(bytes);
  } catch {res.writeHead(404);res.end();}
});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const report={shots:{},errors:[]};let browser;
try {
  browser=await chromium.launch({headless:true,executablePath:args.browser,args:['--use-angle=metal','--ignore-gpu-blocklist','--force-color-profile=srgb','--mute-audio']});
  const page=await browser.newPage({viewport:{width:Number(args.width??1024),height:Number(args.height??1066)},deviceScaleFactor:1});
  // Observe the actual engine context and time submitted frames where the
  // browser exposes disjoint GPU timers. Absence is reported, never guessed.
  await page.addInitScript(()=>{
    const original=HTMLCanvasElement.prototype.getContext;
    window.__gpu={samples:[],info:null,frames:0};
    HTMLCanvasElement.prototype.getContext=function(type,...args){
      const gl=original.call(this,type,...args);
      if(type==='webgl2' && gl && !window.__gpu.info){
        const debug=gl.getExtension('WEBGL_debug_renderer_info');
        const timer=gl.getExtension('EXT_disjoint_timer_query_webgl2');
        window.__gpu.info={version:gl.getParameter(gl.VERSION),renderer:debug?gl.getParameter(debug.UNMASKED_RENDERER_WEBGL):gl.getParameter(gl.RENDERER),
          max_texture_size:gl.getParameter(gl.MAX_TEXTURE_SIZE),fragment_uniform_vectors:gl.getParameter(gl.MAX_FRAGMENT_UNIFORM_VECTORS),timer:!!timer};
        window.__validationGL=gl;
        if(timer){
          const raf=window.requestAnimationFrame.bind(window);let active=false;
          window.requestAnimationFrame=callback=>raf(time=>{
            if(active || gl.isContextLost()){callback(time);return;}
            gl.getExtension("EXT_disjoint_timer_query_webgl2");
            const label=performance.now()<window.__gpu.labelUntil?window.__gpu.label:null;
            const query=gl.createQuery();active=true;gl.beginQuery(timer.TIME_ELAPSED_EXT,query);
            try {callback(time);} finally {gl.endQuery(timer.TIME_ELAPSED_EXT);active=false;}
            const poll=()=>{
              if(gl.isContextLost()) return;
              if(!gl.getQueryParameter(query,gl.QUERY_RESULT_AVAILABLE)){setTimeout(poll,50);return;}
              if(!gl.getParameter(timer.GPU_DISJOINT_EXT)) window.__gpu.samples.push({ms:gl.getQueryParameter(query,gl.QUERY_RESULT)/1e6,label});
              gl.deleteQuery(query);
            };setTimeout(poll,50);
          });
        }
        const countedRAF=window.requestAnimationFrame.bind(window);
        window.requestAnimationFrame=callback=>countedRAF(time=>{callback(time);window.__gpu.frames++;});
      }
      return gl;
    };
  });
  let pending=Promise.resolve(),complete=false;
  page.on('pageerror',e=>report.errors.push(e.message));
  page.on('console',message=>{
    const text=message.text();
    if(text.includes('ERROR:') || /GL_INVALID_|GL_OUT_OF_MEMORY|WebGL:.*error/i.test(text)) report.errors.push(text);
    const match=text.match(/RENDER_BROWSER (SHOT|PASS|RESTORED) (.*)/);
    if(!match) return;
    const data=JSON.parse(match[2]);
    if(match[1]==='RESTORED'){report.restored=data;return;}
    if(match[1]==='PASS'){report.result=data;complete=true;console.log('PASS browser fixture',data.shots);return;}
    pending=pending.then(async()=>{
      await page.evaluate(({id,ms})=>{window.__gpu.label=id;window.__gpu.labelUntil=performance.now()+ms;},
        {id:data.id,ms:Number(args['sample-ms']??350)});
      await page.locator('canvas').screenshot({path:join(output,data.id+'.png')});
      report.shots[data.id]=data;console.log('CAPTURE',data.id);
    });
  });
  await page.goto('http://127.0.0.1:'+server.address().port,{timeout:120000});
  const deadline=Date.now()+Number(args["timeout-ms"]??600000);
  while(!complete && Date.now()<deadline){
    await new Promise(r=>setTimeout(r,500));
    if(report.errors.length) throw new Error(report.errors.join('\n'));
  }
  if(!complete) throw new Error('Rendering browser fixture timed out');
  if(args.release==='1' && report.result.runtime?.profiler!==false)
    throw new Error('Release qualification requires an engine without the debug profiler API');
  await pending;
  if(args.resize==='1'){
    report.resizes=[];
    for(const size of [{width:1279,height:759},{width:961,height:681},{width:1024,height:1066}]){
      const before=await page.evaluate(()=>({frames:window.__gpu.frames,width:window.__validationGL.drawingBufferWidth,height:window.__validationGL.drawingBufferHeight}));
      await page.setViewportSize(size);
      await page.waitForFunction(previous=>window.__gpu.frames>previous.frames+10 &&
        (window.__validationGL.drawingBufferWidth!==previous.width || window.__validationGL.drawingBufferHeight!==previous.height),before,{timeout:15000});
      const result=await page.evaluate(()=>({width:window.__validationGL.drawingBufferWidth,height:window.__validationGL.drawingBufferHeight,error:window.__validationGL.getError()}));
      if(result.error || report.errors.length) throw new Error('WebGL resize failed: '+JSON.stringify(result)+'\n'+report.errors.join('\n'));
      report.resizes.push(result);
    }
    await page.locator('canvas').screenshot({path:join(output,'resized.png')});
  }
  if(args['context-loss']==='1'){
  await page.evaluate(()=>{
    const loss=window.__validationGL.getExtension('WEBGL_lose_context');
    if(!loss) throw new Error('Context-loss test extension unavailable');
    loss.loseContext();setTimeout(()=>loss.restoreContext(),250);
  });
  const restoreDeadline=Date.now()+60000;
  while(!report.restored && Date.now()<restoreDeadline) await new Promise(r=>setTimeout(r,250));
  if(!report.restored) throw new Error('Context restoration did not rebake textures');
  await page.locator('canvas').screenshot({path:join(output,'street_restored.png')});
  }
  report.gpu=await page.evaluate(()=>window.__gpu);
  const samples=report.gpu.samples.map(s=>s.ms).sort((a,b)=>a-b);
  report.gpu.by_shot={};
  for(const name of Object.keys(report.shots)){
    const list=report.gpu.samples.filter(s=>s.label===name).map(s=>s.ms).sort((a,b)=>a-b);
    if(list.length) report.gpu.by_shot[name]={samples:list.length,median_ms:list[Math.floor(list.length*.5)],p95_ms:list[Math.floor(list.length*.95)]};
  }
  report.gpu.frame_gpu_median_ms=samples.length?samples[Math.floor(samples.length*.5)]:null;
  report.gpu.frame_gpu_p95_ms=samples.length?samples[Math.floor(samples.length*.95)]:null;
  report.gpu.scope='Whole rAF submission, including startup baking and diagnostic views; not a sustained-combat GPU budget.';
  if(report.errors.length) throw new Error(report.errors.join('\n'));
  console.log('WEBGL',JSON.stringify(report.gpu.info));
} finally {
  await writeFile(join(output,'report.json'),JSON.stringify(report,null,2)+'\n');
  await browser?.close();await new Promise(r=>server.close(r));
}
