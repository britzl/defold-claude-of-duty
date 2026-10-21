// Real browser input: no autoplay override; touch gestures go through Chromium's input stack.
import {createRequire} from 'node:module';
import {createServer} from 'node:http';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {resolve,join,extname,sep} from 'node:path';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
const args=Object.fromEntries(process.argv.slice(2).map(s=>s.slice(2).split(/=(.*)/s).slice(0,2)));
const root=resolve(args.bundle),output=resolve(args.output??'build/input-browser-validation');
const {chromium}=createRequire(import.meta.url)(process.env.PLAYWRIGHT_MODULE??'playwright');
await mkdir(output,{recursive:true});
const server=createServer(async(req,res)=>{
  try{const path=resolve(root,'.'+(new URL(req.url,'http://localhost').pathname==='/'?'/index.html':decodeURIComponent(new URL(req.url,'http://localhost').pathname)));
    if(!path.startsWith(root+sep)){res.writeHead(403);res.end();return}
    const bytes=await readFile(path);res.writeHead(200,{'Content-Type':({'.wasm':'application/wasm','.js':'application/javascript','.html':'text/html','.json':'application/json'})[extname(path)]??'application/octet-stream'});res.end(bytes);
  }catch{res.writeHead(404);res.end()}
});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const report={checks:[],errors:[],shots:[],bundle:{}};let browser,page;
for(const name of ['ClaudeofDuty.wasm','archive/game0.dmanifest','archive/game0.arcd'])
  report.bundle[name]=createHash('sha256').update(await readFile(join(root,name))).digest('hex');
const check=name=>{report.checks.push(name);console.log('PASS',name)};
try{
  browser=await chromium.launch({headless:true,executablePath:args.browser,args:['--use-angle=metal','--ignore-gpu-blocklist','--force-color-profile=srgb']});
  page=await browser.newPage({viewport:{width:844,height:432},deviceScaleFactor:1,hasTouch:true});
  page.on('pageerror',e=>report.errors.push(e.message));
  page.on('console',m=>{const t=m.text();if(t.includes('ERROR:')||/GL_INVALID_|GL_OUT_OF_MEMORY/.test(t))report.errors.push(t);if(t.includes('ERROR:'))console.log(t)});
  await page.addInitScript(()=>{
    window.__audioContexts=[];const Audio=window.AudioContext;
    if(Audio)window.AudioContext=class extends Audio{constructor(...a){super(...a);window.__audioContexts.push(this)}};
    window.__pad=null;
    const original=navigator.getGamepads.bind(navigator);
    navigator.getGamepads=()=>window.__pad?[window.__pad]:original();
  });
  await page.goto('http://127.0.0.1:'+server.address().port,{waitUntil:'domcontentloaded',timeout:120000});
  await page.waitForFunction(()=>window.__INPUT_STATE__?.ready,{},{timeout:180000});
  const state=()=>page.evaluate(()=>window.__INPUT_STATE__);
  const frames=async(n=6)=>page.evaluate(n=>new Promise(r=>{let i=0;function f(){if(++i>=n)r();else requestAnimationFrame(f)}requestAnimationFrame(f)}),n);
  const command=async data=>{await page.evaluate(d=>window.__INPUT_REQUEST__=d,data);await page.waitForFunction(()=>window.__INPUT_REQUEST__===null);await frames()};
  const wait=async fn=>page.waitForFunction(fn,{},{timeout:30000});
  const cdp=await page.context().newCDPSession(page);let fingers=new Map();
  const canvas=()=>page.locator('canvas').boundingBox();
  const touch=async(id,x,y,phase)=>{
    const box=await canvas();
    const ending=fingers.get(id);
    if(phase==='up')fingers.delete(id);else fingers.set(id,{id,x:box.x+x,y:box.y+y,radiusX:10,radiusY:10,force:1});
    await cdp.send('Input.dispatchTouchEvent',{type:phase==='down'?'touchStart':phase==='up'?'touchEnd':'touchMove',touchPoints:phase==='up'?[ending]:[...fingers.values()]});await frames(6);
    const receipt=await state();(report.gestures??=[]).push({id,phase,look_id:receipt.look_id,held:receipt.held,move_z:receipt.move_z});
  };
  const target=async name=>(await state()).targets[name];
  const tap=async name=>{const p=await target(name);await touch(1,p.x,p.y,'down');await touch(1,p.x,p.y,'up');await frames()};
  const menuTap=async name=>{const p=await page.evaluate(n=>window.__INPUT_MENU__[n],name);assert(p,name);await touch(1,p.x,p.y,'down');await touch(1,p.x,p.y,'up');await frames()};
  const shot=async name=>{await page.locator('canvas').screenshot({path:join(output,name+'.png')});report.shots.push(name)};
  await command({kind:'prepare'});await frames(30);
  // DOM touch activation must unlock browser audio without mouse capture or a shot.
  const p=await target('look');await touch(1,p.x,p.y,'down');await touch(1,p.x,p.y,'up');
  assert.equal((await state()).mouse_locked,false);assert.equal((await state()).weapons.fired,0);
  const audio=await page.evaluate(()=>window.__audioContexts.map(c=>c.state));assert(audio.includes('running'),JSON.stringify(audio));
  report.audio=audio;check('real touch activates browser audio without mouse lock or accidental fire');
  let s=await state(),stick=s.targets.move,fire=s.targets.fire,look=s.targets.look;
  await touch(1,stick.x,stick.y,'down');await touch(2,look.x,look.y,'down');await touch(3,fire.x,fire.y,'down');
  await touch(1,stick.x,stick.y-stick.h*.48);await touch(2,look.x+40,look.y-15);await frames(30);
  let after=await state();assert(after.move_z<-.9&&after.held.fire);assert(after.weapons.fired>s.weapons.fired);assert(Math.abs(after.yaw-s.yaw)>.01);
  await touch(2,0,0,'up');s=await state();await touch(3,fire.x+20,fire.y);assert(Math.abs((await state()).yaw-s.yaw)>.01,JSON.stringify({before:s.yaw,after:(await state()).yaw}));
  await touch(1,0,0,'up');await touch(3,0,0,'up');assert.equal((await state()).move_z,0);assert(!(await state()).held.fire);
  check('three real fingers move, look and fire; fire keeps aiming after look release');
  await tap('aim');await frames(40);assert((await state()).weapons.ads>.9);await tap('aim');
  await tap('crouch');await frames(25);assert.equal((await state()).stance,'crouch');await tap('crouch');
  await tap('reload');await wait(()=>window.__INPUT_STATE__.weapons.clip==='idle');s=await state();await tap('next_weapon');
  await wait(()=>window.__INPUT_STATE__.weapons.clip==='idle');assert.notEqual((await state()).weapons.weapon,s.weapons.weapon);
  check('touch ADS, stance, reload and weapon switching');
  for(const [width,height] of [[844,390],[390,844],[667,375],[1024,768]]){
    await page.setViewportSize({width,height:height+42});await frames(12);await command({kind:'prepare'});
    await shot(`touch_${width}x${height}`);
    await tap('pause');assert((await state()).ui.paused);await menuTap('tab_controls');await shot(`menu_${width}x${height}`);
    await menuTap('setting_invert_look');assert((await state()).ui.input.invert_look);
    const bar=await page.evaluate(()=>window.__INPUT_MENU__.slider_fov);await touch(1,bar.x,bar.y,'down');await touch(1,bar.x+55,bar.y);await touch(1,bar.x+55,bar.y,'up');
    assert((await state()).ui.input.fov>80);await menuTap('defaults');assert.equal((await state()).ui.input.fov,70);assert(!(await state()).ui.input.invert_look);
    await menuTap('tab_display');await menuTap('quality_defaults');await menuTap('setting_mode');
    assert.equal((await state()).ui.quality.mode,'low');await menuTap('quality_defaults');
    assert.equal((await state()).ui.quality.mode,'auto');assert.equal((await state()).ui.quality.active,'high');
    await menuTap('resume');assert(!(await state()).ui.paused);assert(!(await state()).mouse_locked);
  }
  check('phone landscape/portrait and tablet menus: sliders, invert, defaults, resume');
  await page.setViewportSize({width:844,height:432});await frames(12);await command({kind:'prepare'});
  stick=await target('move');fire=await target('fire');
  await touch(1,stick.x,stick.y,'down');await touch(1,stick.x,stick.y-stick.h*.48);await touch(2,fire.x,fire.y,'down');
  await page.setViewportSize({width:390,height:886});await frames(12);
  assert.equal((await state()).move_z,0);assert(!(await state()).held.fire);
  await touch(2,fire.x+5,fire.y);assert(!(await state()).held.fire);
  await touch(1,0,0,'up');await touch(2,0,0,'up');
  await page.setViewportSize({width:844,height:432});await frames(12);await command({kind:'prepare'});
  check('resize releases active fingers and old gestures cannot reacquire controls');
  fire=await target('fire');await touch(4,fire.x,fire.y,'down');await command({kind:'focus',value:false});assert((await state()).ui.paused&&!(await state()).held.fire);
  await command({kind:'focus',value:true});await touch(4,0,0,'up');await menuTap('resume');assert(!(await state()).held.fire);
  await command({kind:'damage'});await wait(()=>!window.__INPUT_STATE__.alive);await tap('pause');await menuTap('restart');assert((await state()).alive);
  check('touch focus loss, death and restart leave no held actions');
  fire=await target('fire');await touch(1,fire.x,fire.y,'down');
  await cdp.send('Input.dispatchTouchEvent',{type:'touchCancel',touchPoints:[]});fingers.clear();await frames(10);
  assert(!(await state()).held.fire);assert.equal((await state()).move_z,0);
  check('browser touch cancellation releases firing');
  // Keyboard events and pointer lock run on the same real page after touch.
  await command({kind:'prepare'});const box=await canvas();s=await state();await page.mouse.click(box.x+box.width/2,box.y+box.height/2,{delay:100});await frames();
  assert(await page.evaluate(()=>document.pointerLockElement===document.querySelector('canvas')));assert.equal((await state()).weapons.fired,s.weapons.fired);
  await page.mouse.move(box.x+box.width/2+50,box.y+box.height/2+20);await frames();assert(Math.abs((await state()).yaw-s.yaw)>.01);
  await page.keyboard.press('3',{delay:100});await wait(()=>window.__INPUT_STATE__.weapons.weapon==='pistol'&&window.__INPUT_STATE__.weapons.clip==='idle');
  await page.mouse.wheel(0,-100);await wait(()=>window.__INPUT_STATE__.weapons.weapon==='smg'&&window.__INPUT_STATE__.weapons.clip==='idle');
  await page.keyboard.press('i',{delay:100});await frames(3);assert.equal((await state()).weapons.clip,'inspect');
  await page.keyboard.press('1',{delay:100});await wait(()=>window.__INPUT_STATE__.weapons.weapon==='rifle'&&window.__INPUT_STATE__.weapons.clip==='idle');
  await page.keyboard.press('c',{delay:100});await frames(25);assert.equal((await state()).stance,'crouch');await page.keyboard.press('z',{delay:100});await frames(25);assert.equal((await state()).stance,'prone');
  await page.keyboard.press('z',{delay:100});await frames(25);assert.equal((await state()).stance,'crouch');await page.keyboard.press('c',{delay:100});await frames(25);
  await page.keyboard.press('Escape',{delay:100});await frames();assert((await state()).ui.paused);assert(!await page.evaluate(()=>document.pointerLockElement));
  check('real mouse capture, keyboard weapon/stance bindings and wheel direction');
  // Poll a standard Gamepad API object through Defold's mapped browser driver.
  await command({kind:'prepare'});
  await page.evaluate(()=>{window.__pad={id:'Standard Gamepad',index:0,connected:true,mapping:'standard',timestamp:performance.now(),axes:[0,0,0,0],buttons:Array.from({length:17},()=>({pressed:false,touched:false,value:0}))};const e=new Event('gamepadconnected');e.gamepad=window.__pad;window.dispatchEvent(e)});
  const pad=async(buttons={},axes=[0,0,0,0])=>{await page.evaluate(({buttons,axes})=>{window.__pad.axes=axes;for(let i=0;i<17;i++)window.__pad.buttons[i]={pressed:!!buttons[i],touched:!!buttons[i],value:buttons[i]??0};window.__pad.timestamp=performance.now()},{buttons,axes});await frames(12)};
  s=await state();await pad({7:1},[0,-1,.6,0]);after=await state();assert(after.move_z<-.9&&after.weapons.fired>s.weapons.fired);assert(Math.abs(after.yaw-s.yaw)>.01);
  await pad();assert.equal((await state()).move_z,0);assert(!(await state()).held.fire);
  await pad({9:1});assert((await state()).ui.paused);await pad();await pad({0:1});await pad();assert(!(await state()).ui.paused);
  await pad({7:1});await page.evaluate(()=>{window.__pad.connected=false;const e=new Event('gamepaddisconnected');e.gamepad=window.__pad;window.dispatchEvent(e);window.__pad=null});await frames(12);
  assert((await state()).ui.paused&&!(await state()).held.fire);
  check('standard browser gamepad mapping, analog move/look, fire, menus and disconnect');
  assert.deepEqual(report.errors,[]);
}catch(error){report.failure=error.stack;if(page)report.state=await page.evaluate(()=>({state:window.__INPUT_STATE__,guard:window.__codTouchMouseGuard,pointer:!!document.pointerLockElement,touchCount:window.__codTouchCount,lastTouch:window.__codLastTouch,now:performance.now()})).catch(()=>null);if(page)await page.screenshot({path:join(output,'failure.png')}).catch(()=>{});throw error;}finally{
  if(page&&report.errors.length)await page.screenshot({path:join(output,'failure.png')}).catch(()=>{});
  await writeFile(join(output,'report.json'),JSON.stringify(report,null,2)+'\n');
  await browser?.close();await new Promise(r=>server.close(r));
}
