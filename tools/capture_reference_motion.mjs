// Three.js motion reference through its existing shot API; source stays untouched.
import {createRequire} from 'node:module';
import {spawn} from 'node:child_process';
import {mkdir,writeFile,readFile,readdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {resolve,join} from 'node:path';
const args=Object.fromEntries(process.argv.slice(2).map(s=>s.slice(2).split(/=(.*)/s).slice(0,2)));
if(!args.source||!args.output)throw Error('Supply --source and --output');
const source=resolve(args.source),out=resolve(args.output);await mkdir(out,{recursive:true});
const {chromium}=createRequire(join(source,'package.json'))('playwright');
const port=Number(args.port??5437);
const server=spawn(process.execPath,[join(source,'node_modules/vite/bin/vite.js'),'--host','127.0.0.1','--port',String(port),'--strictPort'],{cwd:source,stdio:['ignore','pipe','pipe']});
let browser;const report={engine:'Three.js source archive',method:'Fixed 60 Hz reference simulation. Comparable actions; cameras, materials and exposure are not identical.',shots:[],errors:[]};
const digest=createHash('sha256');
async function fingerprint(dir){for(const entry of (await readdir(join(source,dir),{withFileTypes:true})).sort((a,b)=>a.name.localeCompare(b.name))){
 const path=join(dir,entry.name);if(entry.isDirectory())await fingerprint(path);
 else if(entry.name.endsWith('.js')){digest.update(path);digest.update(await readFile(join(source,path)));}
}}
await fingerprint('src');digest.update(await readFile(join(source,'package-lock.json')));report.source_sha256=digest.digest('hex');
try{
 for(let i=0;i<100;i++){try{if((await fetch('http://127.0.0.1:'+port)).ok)break;}catch{}await new Promise(r=>setTimeout(r,100));}
 browser=await chromium.launch({headless:true,executablePath:args.browser,args:['--use-angle=metal','--ignore-gpu-blocklist','--mute-audio']});
 const page=await browser.newPage({viewport:{width:1280,height:720},deviceScaleFactor:1});
 page.on('pageerror',e=>report.errors.push(e.message));
 await page.goto(`http://127.0.0.1:${port}/?capture=1&lockstep=1&q=high`,{timeout:120000});
 await page.waitForFunction(()=>window.__READY__,{timeout:120000});
 await page.evaluate(()=>{
   window.__SHOTS__.review={pos:[0,1.62,10],look:[0,1.62,0],fov:75,time:14,apply:e=>{window.__REVIEW_ENGINE__=e;}};
   window.__APPLY_SHOT__('review');
   const e=window.__REVIEW_ENGINE__,w=e.ctx.peek('weapons');
   w.debugMode=null;w.viewmodel.debugFrozen=false;e.input.enabled=true;e.input.frozen=false;
 });
 async function pump(n){await page.evaluate(n=>window.__PUMP__(n),n);}
 async function snap(name){await page.screenshot({path:join(out,name+'.png')});report.shots.push(name);}
 await pump(90);
 for(const name of ['rifle','smg','pistol']){
   await page.evaluate(name=>{const e=window.__REVIEW_ENGINE__,w=e.ctx.peek('weapons');e.input.down.clear();w.setWeaponImmediate(name);w.viewmodel.stopClip();},name);
   await pump(60);await snap(name+'_hip');
   await page.evaluate(()=>window.__REVIEW_ENGINE__.input.down.add('Mouse2'));
   await pump(60);await snap(name+'_ads');
   await page.evaluate(()=>{const e=window.__REVIEW_ENGINE__;e.input._pendingDown.add('Mouse0');});
   await pump(45);await snap(name+'_fire');
   await page.evaluate(()=>{const e=window.__REVIEW_ENGINE__;e.input.down.clear();e.ctx.peek('weapons').reload();});
   for(let frame=0;frame<120;frame+=15){await pump(15);await snap(name+'_reload_'+(frame+15));}
   await pump(120);
 }
 await page.evaluate(()=>{const e=window.__REVIEW_ENGINE__;e.input.down.clear();e.ctx.peek('fx').debugBurst('none');
   e.ctx.peek('fx').explosion({position:{x:1,y:.15,z:6},radius:3.6,damage:120});});
 for(let frame=0;frame<150;frame+=10){await pump(10);await snap('explosion_'+(frame+10));}
 if(report.errors.length)throw Error(report.errors.join('\n'));
 console.log('PASS',report.shots.length,'reference frames');
} finally {if(browser)await browser.close();server.kill();await writeFile(join(out,'report.json'),JSON.stringify(report,null,2)+'\n');}
