// Full-map browser smoke. Build with --settings tests/market_browser.project.
import {createRequire} from 'node:module';
import {createServer} from 'node:http';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {resolve,join,extname,sep} from 'node:path';
const args=Object.fromEntries(process.argv.slice(2).map(s=>s.slice(2).split(/=(.*)/s).slice(0,2)));
if(!args.bundle) throw new Error('Supply --bundle=/path/to/HTML5/bundle');
const root=resolve(args.bundle), output=resolve(args.output??'build/full-market-browser-validation');
await readFile(join(root,'index.html')); // Fail before starting Chromium if the bundle path is wrong.
const {chromium}=createRequire(import.meta.url)(process.env.PLAYWRIGHT_MODULE??'playwright');
await mkdir(output,{recursive:true});
const types={'.wasm':'application/wasm','.js':'application/javascript','.html':'text/html','.json':'application/json'};
const server=createServer(async(req,res)=>{
  try {
    const relative=decodeURIComponent(new URL(req.url,'http://localhost').pathname);
    const path=resolve(root,'.'+(relative==='/'?'/index.html':relative));
    if(!path.startsWith(root+sep)) {res.writeHead(403);res.end();return;}
    const bytes=await readFile(path);res.writeHead(200,{'Content-Type':types[extname(path)]??'application/octet-stream'});res.end(bytes);
  } catch {res.writeHead(404);res.end();}
});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const report={errors:[],routes:[],shots:[]};let browser;
try {
  browser=await chromium.launch({headless:true,executablePath:args.browser,args:['--use-angle=metal','--ignore-gpu-blocklist','--force-color-profile=srgb','--mute-audio']});
  const page=await browser.newPage({viewport:{width:1280,height:762},deviceScaleFactor:1});
  let complete=false,pending=Promise.resolve();
  page.on('pageerror',e=>report.errors.push(e.message));
  page.on('console',message=>{
    const text=message.text();
    if(text.includes('ERROR:') || /GL_INVALID_|GL_OUT_OF_MEMORY|WebGL:.*error/i.test(text)) report.errors.push(text);
    const match=text.match(/MARKET_BROWSER (PHYSICS|ROUTES|SHOT|PASS) (.*)/);
    if(!match) return;
    const data=JSON.parse(match[2]);
    console.log(match[1],JSON.stringify(data));
    if(match[1]==='PHYSICS') report.physics=data;
    if(match[1]==='ROUTES') report.routes.push(data);
    if(match[1]==='PASS') {report.result=data;complete=true;}
    if(match[1]==='SHOT') pending=pending.then(async()=>{
      await page.locator('canvas').screenshot({path:join(output,data.id+'.png')});report.shots.push(data.id);
    });
  });
  await page.goto('http://127.0.0.1:'+server.address().port,{timeout:120000});
  const deadline=Date.now()+180000;
  while(!complete && Date.now()<deadline){
    await new Promise(r=>setTimeout(r,500));
    if(report.errors.length) throw new Error(report.errors.join('\n'));
  }
  if(!complete) throw new Error('Full-map browser fixture timed out');
  await pending;
  if(report.result.routes!==108 || report.shots.length!==8) throw new Error('Incomplete route/capture matrix');
  if(report.errors.length) throw new Error(report.errors.join('\n'));
  report.webgl=await page.evaluate(()=>{
    const gl=document.querySelector('canvas').getContext('webgl2');
    const debug=gl.getExtension('WEBGL_debug_renderer_info');
    return {version:gl.getParameter(gl.VERSION),renderer:gl.getParameter(debug?debug.UNMASKED_RENDERER_WEBGL:gl.RENDERER)};
  });
} finally {
  await writeFile(join(output,'report.json'),JSON.stringify(report,null,2)+'\n');
  if(browser) await browser.close();
  await new Promise(r=>server.close(r));
}
