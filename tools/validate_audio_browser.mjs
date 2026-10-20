// Real Wasm verification and alternating fresh Lua/native synthesis launches.
// PLAYWRIGHT_MODULE=/path/to/playwright node tools/validate_audio_browser.mjs --bundle=/path --output=/path
import {createRequire} from 'node:module';
import {createServer} from 'node:http';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {resolve,join,extname,sep} from 'node:path';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
const args=Object.fromEntries(process.argv.slice(2).map(s=>s.slice(2).split(/=(.*)/s).slice(0,2)));
assert(args.bundle,'Supply --bundle=/path/to/HTML5/bundle');
const root=resolve(args.bundle),output=resolve(args.output??'captures/native-audio/browser');
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
            const flags=[`--config=audio_synthesis.backend=${backend}`,
                `--config=audio_synthesis.verify=${url.searchParams.get('verify')==='1'?1:0}`,
                '--config=audio_synthesis.fingerprints=1','--config=world_mesh.backend=native',
                '--config=audio_validation.enabled=1','--config=market_validation.enabled=0','--config=mesh_validation.enabled=0'];
            bytes=html.replace('EngineLoader.load(',`CUSTOM_PARAMETERS.engine_arguments.push(...${JSON.stringify(flags)});EngineLoader.load(`);
        } else bytes=await readFile(path);
        res.writeHead(200,{'Content-Type':types[extname(path)]??'application/octet-stream'});res.end(bytes);
    } catch {res.writeHead(404);res.end();}
});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const report={runs:[],errors:[],bundle:root,viewport:{width:960,height:640},device_scale_factor:1};
let browser;
try {
    for(const file of ['index.html','ClaudeofDuty.wasm','archive/archive_files.json','archive/game0.arcd'])
        report[file+'_sha256']=createHash('sha256').update(await readFile(join(root,file))).digest('hex');
    const sequence=[{backend:'native',verify:true}];
    for(let i=0;i<Number(args.runs??3);i++) for(const backend of ['lua','native']) sequence.push({backend,verify:false});
    for(const config of sequence) {
        browser=await chromium.launch({headless:true,executablePath:args.browser,
            args:['--use-angle=metal','--ignore-gpu-blocklist','--mute-audio']});
        const page=await browser.newPage({viewport:report.viewport,deviceScaleFactor:1});
        const run={...config,errors:[],samples:[],browser_version:browser.version()};report.active_run=run;
        page.on('pageerror',e=>run.errors.push(e.message));
        page.on('console',message=>{
            const text=message.text();
            if(text.includes('ERROR:') || /GL_INVALID_|GL_OUT_OF_MEMORY|WebGL:.*error/i.test(text)) run.errors.push(text);
            if(text.includes('NATIVE_AUDIO_TEST PASS')) run.fixture_pass=text;
            const match=text.match(/AUDIO_BROWSER (READY|SAMPLE|PASS) (.*)/);
            if(match) try {
                const data=JSON.parse(match[2]);
                if(match[1]==='READY') run.result=data;
                if(match[1]==='SAMPLE') run.samples.push(data);
                if(match[1]==='PASS') run.complete=data;
            } catch(error) {run.errors.push(String(error));}
        });
        await page.goto(`http://127.0.0.1:${server.address().port}/index.html?backend=${config.backend}&verify=${Number(config.verify)}`,{timeout:120000});
        const deadline=Date.now()+120000;
        while(!run.complete && Date.now()<deadline) {
            assert.deepEqual(run.errors,[]);
            await new Promise(r=>setTimeout(r,100));
        }
        assert(run.complete,'Audio browser fixture timed out');assert.deepEqual(run.errors,[]);
        const audio=run.result.audio;
        assert.equal(audio.synthesis_backend,config.backend);assert(audio.ready);
        assert.equal(audio.loaded,77);assert.equal(audio.bytes,1698124);assert.equal(run.samples.length,77);
        assert.equal(run.complete.samples,77);
        assert.equal(run.result.world.vertices,413568);
        if(config.verify) {assert(run.fixture_pass);assert.equal(audio.verified,77);}
        report.runs.push(run);delete report.active_run;
        console.log('PASS',config,'audio CPU',audio.work_ms,'timings',run.result.timings);
        await browser.close();browser=null;
        await writeFile(join(output,'report.json'),JSON.stringify(report,null,2)+'\n');
    }
    const baseline=report.runs.find(r=>r.backend==='lua').samples;
    for(const run of report.runs) for(const [i,sample] of run.samples.entries()) {
        const reference=baseline[i];
        for(const key of ['key','hash','bytes','frames','duration']) assert.equal(sample[key],reference[key],`${sample.key} ${key}`);
        for(const key of ['peak','rms']) assert(Math.abs(sample[key]-reference[key])<=1e-12,`${sample.key} ${key}`);
    }
    report.complete=true;
} catch(error) {report.errors.push(String(error));throw error;}
finally {
    await writeFile(join(output,'report.json'),JSON.stringify(report,null,2)+'\n');
    if(browser) await browser.close();await new Promise(r=>server.close(r));
}
