// Use the reference's own deterministic shutter without changing its source.
// node tools/capture_reference.mjs --source=/path/to/Claude-of-Duty-main --baseline=/path/to/defold/manifest.json
import { createRequire } from 'node:module';
import { spawn, execFileSync } from 'node:child_process';
import { readFile, writeFile, mkdir, readdir, access } from 'node:fs/promises';
import { resolve, join, dirname } from 'node:path';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { captureRequest, selectShots, validateAppliedState } from './reference_contract.mjs';
import { installLaboratory } from './reference_laboratory.mjs';

const args = Object.fromEntries(process.argv.slice(2).map(v => {
  const match = v.match(/^--([^=]+)=(.*)$/);
  if (!match) throw new Error(`Expected --key=value: ${v}`);
  return [match[1], match[2]];
}));
if (!args.source || !args.baseline) throw new Error('Supply --source and --baseline');
const source = resolve(args.source);
const baseline = JSON.parse(await readFile(resolve(args.baseline), 'utf8'));
const catalog = baseline.catalog ?? baseline;
const selected = selectShots(catalog, args.shots);
const repeats = Number(args.repeats ?? 1);
if (!Number.isInteger(repeats) || repeats < 1 || repeats > 5) throw new Error('repeats must be 1..5');
const browserBatch = Number(args['browser-batch'] ?? 8);
if (!Number.isInteger(browserBatch) || browserBatch < 1 || browserBatch > 32) throw new Error('browser-batch must be 1..32');
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const fixture = JSON.parse(execFileSync('lua', ['tools/export_parity.lua', 'laboratory'], { cwd: root, maxBuffer: 16 * 1024 * 1024 }));
const output = resolve(args.output ?? `captures/rendering/threejs-${new Date().toISOString().replace(/[:.]/g, '-')}`);
const port = Number(args.port ?? 5417);
const requireReference = createRequire(join(source, 'package.json'));
const { chromium } = requireReference('playwright');
const { PNG } = requireReference('pngjs');
const digest = createHash('sha256');
async function fingerprint(directory) {
  for (const entry of (await readdir(join(source, directory), { withFileTypes: true })).sort((a,b) => a.name.localeCompare(b.name))) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) await fingerprint(path);
    else if (entry.name.endsWith('.js')) { digest.update(path); digest.update(await readFile(join(source, path))); }
  }
}
await fingerprint('src');
digest.update(await readFile(join(source, 'package-lock.json')));
await mkdir(dirname(output), { recursive: true });
await mkdir(output); // Never overwrite another run's evidence.
let revision = null;
try {
  await access(join(source, '.git')); // Do not inherit an unrelated parent checkout.
  revision = execFileSync('git', ['-C', source, 'rev-parse', 'HEAD'], { stdio: ['ignore', 'pipe', 'ignore'], encoding: 'utf8' }).trim();
} catch {}
const report = { schema_version: 2, engine: 'threejs', source, revision, source_sha256: digest.digest('hex'),
  fingerprint_method: 'Sorted src/**/*.js: relative path then bytes; followed by package-lock.json bytes (legacy adapter format).',
  revision_status: revision ? 'git checkout' : 'Source archive: exact revision unavailable; use source hash',
  created_utc: new Date().toISOString(), catalog_version: catalog.version,
  catalog_sha256: createHash('sha256').update(JSON.stringify(catalog)).digest('hex'),
  source_seed: 0x5eed1234, quality: 'ultra', baseline: resolve(args.baseline),
  width: catalog.width, height: catalog.height,
  comparison: 'Adapted level-space framing. Scene generation, lighting, exposure models and quality budgets differ; no cross-engine pixel equality or performance claim.',
  exposure_policy: 'Reference GPU meter sampled after 90 lockstep frames with fixed time; actual multiplier recorded per shot. Defold fixed exposure is not assumed equivalent.',
  requested_shots: selected.map(s => s.id), catalog_shot_count: catalog.shots.length,
  repeats, browser_page_limit: browserBatch, browser_launches: 0,
  settle_frames: 90, shots: {}, pending_shots: [], complete: false };
report.adapter_sha256 = createHash('sha256').update(await readFile(fileURLToPath(import.meta.url)))
  .update(await readFile(join(root, 'tools/reference_contract.mjs')))
  .update(await readFile(join(root, 'tools/reference_laboratory.mjs'))).update(JSON.stringify(fixture)).digest('hex');
const server = spawn(process.execPath, [join(source, 'node_modules/vite/bin/vite.js'), '--host', '127.0.0.1', '--port', String(port), '--strictPort'],
  { cwd: source, env: { ...process.env, OW_NO_HMR: '1' }, stdio: ['ignore', 'pipe', 'pipe'] });
let serverLog = '', serverExited = false;
server.stdout.on('data', chunk => { serverLog += chunk; });
server.stderr.on('data', chunk => { serverLog += chunk; });
server.on('exit', () => { serverExited = true; });
server.on('error', error => { serverLog += error.message; serverExited = true; });
let browser;
let browserPages = 0;
const browserOptions = { headless: true,
  args: ['--use-angle=metal', '--ignore-gpu-blocklist', '--force-color-profile=srgb', '--mute-audio'] };
try {
  for (let i = 0; i < 100; i++) {
    if (serverExited) throw new Error(serverLog);
    if (serverLog.includes('Local:')) break;
    await new Promise(r => setTimeout(r, 100));
  }
  if (!serverLog.includes('Local:')) throw new Error(`Reference server did not become ready: ${serverLog}`);
  for (const shot of selected) {
    const request = captureRequest(shot);
    if (request.status !== 'supported') {
      report.shots[shot.id] = request;
      report.pending_shots.push(shot.id);
      continue;
    }
    for (let repeat = 1; repeat <= repeats; repeat++) {
    // Bound browser/GPU lifetime during long catalogues, including after page.close().
    if (!browser || browserPages >= browserBatch) {
      if (browser) await browser.close();
      browser = await chromium.launch(browserOptions);
      report.browser_launches++;
      report.browser_version = browser.version();
      browserPages = 0;
    }
    browserPages++;
    const page = await browser.newPage({ viewport: { width: report.width, height: report.height }, deviceScaleFactor: 1 });
    const errors = [];
    page.on('pageerror', e => errors.push(e.message));
    try {
      await page.goto(`http://127.0.0.1:${port}/?capture=1&lockstep=1&q=ultra`, { timeout: 120000 });
      await page.waitForFunction(() => window.__READY__ === true, null, { timeout: 120000 });
      await page.addStyleTag({ content: '#ui { display: none !important; }' });
      const laboratory = request.laboratory ? await page.evaluate(installLaboratory, fixture) : null;
      const state = await page.evaluate(async ({ shot, request, settle }) => {
        const e = window.__ENGINE__, world = e.ctx.get('world');
        const applied = window.__APPLY_SHOT__(shot.reference || 'hero', { grabFrame: settle });
        if (applied.error) throw new Error(applied.error);
        const eye = world.levelToWorld(...shot.position);
        const target = world.levelToWorld(...shot.target);
        e.camera.position.copy(eye); e.camera.lookAt(target);
        e.camera.fov = shot.fov; e.camera.near = .1; e.camera.far = 500; e.camera.updateProjectionMatrix();
        e.ctx.get('player').teleport(eye, e.camera.rotation);
        const sky = e.ctx.get('sky');
        sky.setTimeRate(0);
        if (!request.clouds) sky.setWeather({ cloudCoverage: 0, cirrusCoverage: 0, cirrusOpacity: 0 });
        sky.setTimeOfDay(request.hour);
        e.ctx.get('ai').root.visible = false;
        // Freeze combat while allowing deterministic renderer/exposure convergence.
        e.time.scale = 0;
        const weapons = e.ctx.get('weapons');
        weapons.debugPose(request.pose);
        // debugPose resets to the rifle, so selection must follow that reset.
        if (request.weapon && !weapons.setWeaponImmediate(request.weapon)) throw new Error('Weapon selection failed');
        e.viewScene.visible = !!shot.weapon;
        await window.__PUMP__(settle);
        await window.__PRESENT__();
        const r = e.ctx.get('render');
        const gl = r.renderer.getContext(), ext = gl.getExtension('WEBGL_debug_renderer_info');
        return { camera: { position: e.camera.position.toArray(), quaternion: e.camera.quaternion.toArray(),
                  vertical_fov: e.camera.fov, near: e.camera.near, far: e.camera.far,
                  level_position: shot.position, level_target: shot.target },
          level_to_world_matrix: world.A.xform.toArray(),
          hour: sky.timeOfDay, sun_direction: sky.sunDirection.toArray(), weather: {...sky.weather}, settings: {...r.settings},
          quality: e.ctx.config.q, deterministic: e.ctx.config.deterministic,
          source_shot: shot.reference || 'hero', render: window.__RENDER_INFO__,
          exposure: r.debugExposure(), display_exposure: e.ctx.config.exposure ?? 1, frame: e.time.frame,
          gpu: { renderer: ext ? gl.getParameter(ext.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER),
            version: gl.getParameter(gl.VERSION), width: gl.drawingBufferWidth, height: gl.drawingBufferHeight },
          hud: false, actors: false, weapon: shot.weapon || 'hidden', weapon_id: request.weapon ? weapons.activeId : null };
      }, { shot, request, settle: report.settle_frames });
      if (errors.length) throw new Error(errors.join('\n'));
      validateAppliedState(state, shot, request, report);
      const image = `${shot.id}${repeat === 1 ? '' : '-repeat-' + repeat}.png`;
      await page.screenshot({ path: join(output, image) });
      const bytes = await readFile(join(output, image));
      const hash = createHash('sha256').update(bytes).digest('hex');
      if (repeat === 1) report.shots[shot.id] = { status: 'captured', image, sha256: hash, laboratory, ...state, repeats: [] };
      else {
        const first = PNG.sync.read(await readFile(join(output, report.shots[shot.id].image)));
        const again = PNG.sync.read(bytes);
        const identical = first.width === again.width && first.height === again.height && first.data.equals(again.data);
        report.shots[shot.id].repeats.push({ image, sha256: hash, identical });
        if (!identical) throw new Error(`Repeat pixels differ: ${shot.id}`);
      }
      console.log('CAPTURE', shot.id, 'repeat', repeat, 'frame', state.frame);
      await writeFile(join(output, 'manifest.json'), JSON.stringify(report, null, 2) + '\n');
    } catch (error) {
      report.shots[shot.id] = { ...report.shots[shot.id], status: 'failed', reason: error.message };
      throw error;
    } finally { await page.close(); }
    }
  }
  report.complete = report.pending_shots.length === 0;
} catch (error) {
  report.error = error.message;
  throw error;
} finally {
  if (browser) await browser.close();
  server.kill();
  await writeFile(join(output, 'manifest.json'), JSON.stringify(report, null, 2) + '\n');
}
console.log('REFERENCE', output);
