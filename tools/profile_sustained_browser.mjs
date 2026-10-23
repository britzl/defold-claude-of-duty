// Build release with tests/sustained.project; runs the same workload as native.
import {createRequire} from 'node:module';
import {createServer} from 'node:http';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {resolve,join,extname,sep} from 'node:path';
const args=Object.fromEntries(process.argv.slice(2).map(s=>s.slice(2).split(/=(.*)/s).slice(0,2)));
if(!args.bundle) throw new Error('Supply --bundle=/path/to/HTML5/bundle');
const runs=Number(args.runs??3);
const options={warmup:Number(args.warmup??60),seconds:Number(args.seconds??300),preset:args.preset??'high',
  renderer:JSON.parse(args.renderer??'{}'),no_ai:args['no-ai']==='1',no_origin_index:args['no-origin-index']==='1'};
if(!options.renderer||typeof options.renderer!=='object'||Array.isArray(options.renderer))throw new Error('renderer must be a JSON object');
if(!Number.isInteger(runs)||runs<1||!Number.isFinite(options.warmup)||options.warmup<0||!Number.isFinite(options.seconds)||options.seconds<=0)
  throw new Error('runs and seconds must be positive; warmup must be nonnegative');
if(!['auto','low','medium','high','ultra'].includes(options.preset))throw new Error('Invalid preset');
const root=resolve(args.bundle), output=resolve(args.output??'build/quality-performance-browser');
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

const {execFileSync}=await import('node:child_process');
const {createHash}=await import('node:crypto');
const bundle={};
for(const name of ['ClaudeofDuty.wasm','archive/game0.dmanifest','archive/game0.arcd'])bundle[name]=createHash('sha256').update(await readFile(join(root,name))).digest('hex');
const reports=[];
try {
  for(let run=1;run<=runs;run++) {
    const errors=[];let browser;
    try {
      browser=await chromium.launch({headless:args.headed!=='1',executablePath:args.browser,args:['--autoplay-policy=no-user-gesture-required','--use-angle=metal','--ignore-gpu-blocklist','--force-color-profile=srgb','--mute-audio']});
      const page=await browser.newPage({viewport:{width:1280,height:762},deviceScaleFactor:1});
      const session=await browser.newBrowserCDPSession();
      const cpu=args['cpu-profile']==='1'?await page.context().newCDPSession(page):null;
      if(cpu){await cpu.send('Profiler.enable');await cpu.send('Profiler.setSamplingInterval',{interval:1000});}
      await page.addInitScript(options=>{window.__SUSTAINED_OPTIONS__=options},options);
      if(args['gpu-timing']==='1')await page.addInitScript(()=>{
        const getContext=HTMLCanvasElement.prototype.getContext;
        window.__BENCHMARK_GPU__={available:false,samples:[],disjoint:0};
        HTMLCanvasElement.prototype.getContext=function(type,...args){
          const gl=getContext.call(this,type,...args);
          if(type!=='webgl2'||!gl||window.__BENCHMARK_GPU__.installed)return gl;
          const state=window.__BENCHMARK_GPU__;state.installed=true;
          const ext=gl.getExtension('EXT_disjoint_timer_query_webgl2');
          state.available=!!ext;if(!ext)return gl;
          const request=window.requestAnimationFrame.bind(window);let active=false,frame=0;
          const pending=[];
          window.requestAnimationFrame=callback=>request(time=>{
            if(active||gl.isContextLost()){callback(time);return;}
            const disjoint=gl.getParameter(ext.GPU_DISJOINT_EXT);
            if(disjoint){state.disjoint++;for(const p of pending)gl.deleteQuery(p.query);pending.length=0;}
            while(pending.length&&gl.getQueryParameter(pending[0].query,gl.QUERY_RESULT_AVAILABLE)){
              const p=pending.shift();
              state.samples.push({elapsed:p.elapsed,ms:gl.getQueryParameter(p.query,gl.QUERY_RESULT)/1e6});gl.deleteQuery(p.query);
            }
            if(++frame%10!==0||pending.length>=4||window.__SUSTAINED_RESULT__){callback(time);return;}
            const query=gl.createQuery();active=true;gl.beginQuery(ext.TIME_ELAPSED_EXT,query);
            try{callback(time);}finally{gl.endQuery(ext.TIME_ELAPSED_EXT);active=false;pending.push({query,elapsed:performance.now()/1000});}
          });
          return gl;
        };
      });
      if(args['callback-timing']==='1')await page.addInitScript(()=>{
        const request=window.requestAnimationFrame;
        const times=[];window.__BENCHMARK_CALLBACK_MS__=times;
        let finished=false;
        window.requestAnimationFrame=function(callback){return request.call(window,time=>{
          const start=performance.now();
          try {callback(time)} finally {
            if(window.__SUSTAINED_RESULT__)finished=true;
            if(!finished)times.push(performance.now()-start);
          }
        })};
      });
      page.on('pageerror',e=>errors.push(e.message));
      page.on('console',m=>{const t=m.text();if(t.includes('ERROR:')||/GL_INVALID_|GL_OUT_OF_MEMORY|WebGL:.*error/i.test(t))errors.push(t);if(t.startsWith('SUSTAINED'))console.log(t)});
      const start=Date.now();
      await page.goto('http://127.0.0.1:'+server.address().port,{waitUntil:'domcontentloaded',timeout:120000});
      let profiling=false;
      const memory=[];let result;
      const deadline=Date.now()+(options.warmup+options.seconds+150)*1000;
      while(Date.now()<deadline) {
        if(errors.length)throw Error(errors.join('\n'));
        result=await page.evaluate(()=>window.__SUSTAINED_RESULT__??null);
        if(result)break;
        if(cpu&&!profiling&&(Date.now()-start)/1000>=options.warmup+5){await cpu.send('Profiler.start');profiling=true;}
        const {processInfo}=await session.send('SystemInfo.getProcessInfo');
        const ids=processInfo.map(p=>p.id);
        const rss=execFileSync('ps',['-o','rss=','-p',ids.join(',')],{encoding:'utf8'}).trim().split(/\s+/).reduce((sum,n)=>sum+Number(n),0)/1024;
        memory.push({elapsed:(Date.now()-start)/1000,rss_mib:rss,cpu_seconds:processInfo.reduce((sum,p)=>sum+p.cpuTime,0)});
        await new Promise(r=>setTimeout(r,1000));
      }
      if(!result)throw Error('Sustained fixture timeout: '+JSON.stringify(await page.evaluate(()=>window.__SUSTAINED_LOADING__)));
      if(cpu&&profiling){
        const {profile}=await cpu.send('Profiler.stop');
        await writeFile(join(output,`run-${run}.cpuprofile`),JSON.stringify(profile));
        result.cpu_profile_scope='Sampled browser main-thread JS/Wasm stacks; diagnostic overhead included; not GPU timing';
      }
      if(result.engine.is_debug)throw Error('Release engine required');
      if(result.renderer.output_width!==1280||result.renderer.output_height!==720)throw Error('Wrong framebuffer size');
      result.process_rss_samples=memory;result.process_peak_rss_mib=Math.max(...memory.map(s=>s.rss_mib));
      result.memory_scope='Sum of isolated Chromium browser, renderer and GPU processes; includes browser overhead';
      result.browser=browser.version();result.errors=errors;result.bundle_sha256=bundle;result.process_elapsed_seconds=(Date.now()-start)/1000;
      if(args['callback-timing']==='1') {
        result.callback_wall_ms=await page.evaluate(n=>window.__BENCHMARK_CALLBACK_MS__.slice(-n),result.frames.samples);
        result.callback_metric='requestAnimationFrame callback wall duration, including synchronous driver waits; not pure CPU or GPU time';
      }
      if(args['gpu-timing']==='1') {
        result.gpu_timer=await page.evaluate(()=>window.__BENCHMARK_GPU__);
        result.gpu_timer_scope='Disjoint-checked WebGL queries around every tenth animation callback; includes submission/queue-starvation time and diagnostic overhead, not isolated shader-pass cost';
      }
      result.webgl=await page.evaluate(()=>{const gl=document.querySelector('canvas').getContext('webgl2'),d=gl.getExtension('WEBGL_debug_renderer_info');return {version:gl.getParameter(gl.VERSION),renderer:gl.getParameter(d?d.UNMASKED_RENDERER_WEBGL:gl.RENDERER)}});
      await writeFile(join(output,`run-${run}.json`),JSON.stringify(result,null,2)+'\n');
      await page.locator('canvas').screenshot({path:join(output,`run-${run}.png`)});
      const summary=Object.fromEntries(['frames','loaded_seconds','process_peak_rss_mib','distance','shots','reloads','grenades','kills','restarts','stalls','reached','failure'].map(k=>[k,result[k]]));
      reports.push(summary);console.log('RUN',run,JSON.stringify(summary));
      if(result.failure)throw Error(result.failure);
    } catch(error) {await writeFile(join(output,`failure-${run}.json`),JSON.stringify({error:String(error),errors},null,2)+'\n');throw error
    } finally {if(browser)await browser.close();await writeFile(join(output,'summary.json'),JSON.stringify(reports,null,2)+'\n')}
  }
} finally {await new Promise(r=>server.close(r))}
