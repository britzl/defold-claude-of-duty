// Actual Wasm engine, matched Lua/native launches, full installed stream hashes.
// PLAYWRIGHT_MODULE=/absolute/path/to/playwright node tools/validate_native_mesh_browser.mjs --bundle=... --output=...
import {createRequire} from 'node:module';
import {createServer} from 'node:http';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {resolve,join,extname,sep} from 'node:path';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
const args=Object.fromEntries(process.argv.slice(2).map(s=>s.slice(2).split(/=(.*)/s).slice(0,2)));
assert(args.bundle,'Supply --bundle=/path/to/HTML5/bundle');
const root=resolve(args.bundle),output=resolve(args.output??'captures/native-worldmesh/browser');
const html=await readFile(join(root,'index.html'),'utf8');
assert(html.includes('EngineLoader.load('));
const {chromium}=createRequire(import.meta.url)(process.env.PLAYWRIGHT_MODULE??'playwright');
await mkdir(output,{recursive:true});
const types={'.wasm':'application/wasm','.js':'application/javascript','.html':'text/html','.json':'application/json'};
const server=createServer(async(req,res)=>{
    try {
        const url=new URL(req.url,'http://localhost');
        const path=resolve(root,'.'+decodeURIComponent(url.pathname==='/'?'/index.html':url.pathname));
        if(!path.startsWith(root+sep)) {res.writeHead(403);res.end();return;}
        let bytes;
        if(path===join(root,'index.html')) {
            const backend=url.searchParams.get('backend')==='lua'?'lua':'native';
            const verify=url.searchParams.get('verify')==='1'?1:0;
            const flags=[`--config=world_mesh.backend=${backend}`,`--config=world_mesh.verify=${verify}`,
                '--config=mesh_validation.enabled=1','--config=market_validation.enabled=0','--config=rendering_validation.enabled=0'];
            bytes=html.replace('EngineLoader.load(',`CUSTOM_PARAMETERS.engine_arguments.push(...${JSON.stringify(flags)});EngineLoader.load(`);
        } else bytes=await readFile(path);
        res.writeHead(200,{'Content-Type':types[extname(path)]??'application/octet-stream'});res.end(bytes);
    } catch {res.writeHead(404);res.end();}
});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const report={runs:[],errors:[],bundle:root,viewport:{width:960,height:640},device_scale_factor:1};
let browser;
try {
    for (const file of ['index.html','ClaudeofDuty.wasm','archive/archive_files.json','archive/game0.arcd']) {
        try {report[file+'_sha256']=createHash('sha256').update(await readFile(join(root,file))).digest('hex');} catch {}
    }
    const sequence=[{backend:'native',verify:true}];
    for(let i=0;i<Number(args.runs??3);i++) for(const backend of ['lua','native']) sequence.push({backend,verify:false});
    for(const [index,config] of sequence.entries()) {
        browser=await chromium.launch({headless:true,executablePath:args.browser,args:['--use-angle=metal','--ignore-gpu-blocklist','--force-color-profile=srgb','--mute-audio']});
        const page=await browser.newPage({viewport:report.viewport,deviceScaleFactor:1});
        const run={...config,batches:[],errors:[],browser_version:browser.version()};let complete=false;
        report.active_run=run;
        page.on('pageerror',e=>run.errors.push(e.message));
        page.on('console',message=>{
            const text=message.text();
            if(text.includes('ERROR:') || /GL_INVALID_|GL_OUT_OF_MEMORY|WebGL:.*error/i.test(text)) run.errors.push(text);
            if(text.includes('NATIVE_MESH_TEST PASS')) run.fixture_pass=text;
            const match=text.match(/MESH_BROWSER (READY|BATCH|PASS) (.*)/);
            if(!match) return;
            const data=JSON.parse(match[2]);
            if(match[1]==='READY') {run.ready=data;run.observed_ready_ms=performance.now()-started;}
            if(match[1]==='BATCH') run.batches.push(data);
            if(match[1]==='PASS') {run.result=data;complete=true;}
        });
        const started=performance.now();
        await page.goto(`http://127.0.0.1:${server.address().port}/index.html?backend=${config.backend}&verify=${Number(config.verify)}`,{timeout:120000});
        const deadline=Date.now()+120000;
        while(!complete && Date.now()<deadline) {
            if(run.errors.length) throw new Error(run.errors.join('\n'));
            await new Promise(r=>setTimeout(r,100));
        }
        assert(complete,'Mesh browser fixture timed out');assert.deepEqual(run.errors,[]);
        assert.equal(run.ready.backend,config.backend);assert.equal(run.result.actors,6);
        if(config.verify) assert(run.fixture_pass,'Missing native primitive/ownership checks');
        assert.equal(run.batches.length,65);assert.equal(run.ready.stats.vertices,414432);
        const baseline=report.runs.find(r=>r.backend==='lua');
        if(baseline) assert.deepEqual(run.batches,baseline.batches,'Installed mesh streams/bounds differ');
        if(!config.verify && !report.runs.some(r=>!r.verify && r.backend===config.backend))
            await page.locator('canvas').screenshot({path:join(output,config.backend+'.png')});
        run.webgl=await page.evaluate(()=>{
            const gl=document.querySelector('canvas').getContext('webgl2');const debug=gl.getExtension('WEBGL_debug_renderer_info');
            return {version:gl.getParameter(gl.VERSION),renderer:gl.getParameter(debug?debug.UNMASKED_RENDERER_WEBGL:gl.RENDERER),
                width:gl.drawingBufferWidth,height:gl.drawingBufferHeight};
        });
        report.runs.push(run);delete report.active_run;console.log('PASS',index,config,run.ready.timings);
        await browser.close();browser=null;
        await writeFile(join(output,'report.json'),JSON.stringify(report,null,2)+'\n');
    }
    const baseline=report.runs.find(r=>r.backend==='lua');
    for(const run of report.runs) assert.deepEqual(run.batches,baseline.batches);
    report.complete=true;
} catch(error) {report.errors.push(String(error));throw error;}
finally {
    await writeFile(join(output,'report.json'),JSON.stringify(report,null,2)+'\n');
    if(browser) await browser.close();await new Promise(r=>server.close(r));
}
