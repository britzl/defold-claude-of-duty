// Use the reference's own deterministic shutter without changing its source.
// node tools/capture_reference.mjs --source=/path/to/Claude-of-Duty-main --baseline=/path/to/defold/manifest.json
import { createRequire } from 'node:module';
import { spawn } from 'node:child_process';
import { readFile, writeFile, mkdir, readdir } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { createHash } from 'node:crypto';

const args = Object.fromEntries(process.argv.slice(2).map(v => {
  const match = v.match(/^--([^=]+)=(.*)$/);
  if (!match) throw new Error(`Expected --key=value: ${v}`);
  return [match[1], match[2]];
}));
if (!args.source || !args.baseline) throw new Error('Supply --source and --baseline');
const source = resolve(args.source);
const baseline = JSON.parse(await readFile(resolve(args.baseline), 'utf8'));
const output = resolve(args.output ?? `captures/rendering/threejs-${new Date().toISOString().replace(/[:.]/g, '-')}`);
const port = Number(args.port ?? 5417);
const requireReference = createRequire(join(source, 'package.json'));
const { chromium } = requireReference('playwright');
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
await mkdir(output, { recursive: true });
const report = { engine: 'threejs', source, source_sha256: digest.digest('hex'),
  source_seed: 0x5eed1234, quality: 'ultra', baseline: resolve(args.baseline),
  width: baseline.catalog.width, height: baseline.catalog.height,
  comparison: 'Same level-space cameras transformed with world.levelToWorld; different geometry, seed and daylight lighting. No cross-engine pixel equality.',
  settle_frames: 90, shots: {} };
const server = spawn(process.execPath, [join(source, 'node_modules/vite/bin/vite.js'), '--host', '127.0.0.1', '--port', String(port), '--strictPort'],
  { cwd: source, env: { ...process.env, OW_NO_HMR: '1' }, stdio: ['ignore', 'pipe', 'pipe'] });
let serverLog = '', serverExited = false;
server.stdout.on('data', chunk => { serverLog += chunk; });
server.stderr.on('data', chunk => { serverLog += chunk; });
server.on('exit', () => { serverExited = true; });
let browser;
try {
  for (let i = 0; i < 100; i++) {
    if (serverExited) throw new Error(serverLog);
    if (serverLog.includes('Local:')) break;
    await new Promise(r => setTimeout(r, 100));
  }
  browser = await chromium.launch({ headless: true,
    args: ['--use-angle=metal', '--ignore-gpu-blocklist', '--force-color-profile=srgb', '--mute-audio'] });
  for (const shot of baseline.catalog.shots) {
    if (args.shots && !args.shots.split(',').includes(shot.id)) continue;
    if (shot.laboratory) {
      report.shots[shot.id] = { status: 'pending', reason: 'Laboratory currently exists only in Defold.' };
      continue;
    }
    const page = await browser.newPage({ viewport: { width: report.width, height: report.height }, deviceScaleFactor: 1 });
    const errors = [];
    page.on('pageerror', e => errors.push(e.message));
    try {
      await page.goto(`http://127.0.0.1:${port}/?capture=1&lockstep=1&q=ultra`, { timeout: 120000 });
      await page.waitForFunction(() => window.__READY__ === true, null, { timeout: 120000 });
      await page.addStyleTag({ content: '#ui { display: none !important; }' });
      const state = await page.evaluate(async ({ shot, settle }) => {
        const e = window.__ENGINE__, world = e.ctx.get('world');
        const applied = window.__APPLY_SHOT__(shot.reference || 'hero', { grabFrame: settle });
        if (applied.error) throw new Error(applied.error);
        const eye = world.levelToWorld(...shot.position);
        const target = world.levelToWorld(...shot.target);
        e.camera.position.copy(eye); e.camera.lookAt(target);
        e.camera.fov = shot.fov; e.camera.updateProjectionMatrix();
        e.ctx.get('player').teleport(eye, e.camera.rotation);
        e.ctx.get('sky').setTimeOfDay(shot.requested_hour ?? 16.5);
        e.ctx.get('ai').root.visible = false;
        // Freeze combat while allowing deterministic renderer/exposure convergence.
        e.time.scale = 0;
        e.ctx.get('weapons').debugPose(shot.weapon === 'ads' ? 'ads' : 'idle');
        e.viewScene.visible = !!shot.weapon;
        await window.__PUMP__(settle);
        await window.__PRESENT__();
        const r = e.ctx.get('render'), sky = e.ctx.get('sky');
        return { camera: { position: e.camera.position.toArray(), quaternion: e.camera.quaternion.toArray(),
                  vertical_fov: e.camera.fov, level_position: shot.position, level_target: shot.target },
          hour: sky.timeOfDay, sun_direction: sky.sunDirection.toArray(), settings: r.settings,
          source_shot: shot.reference || 'hero', render: window.__RENDER_INFO__,
          exposure: window.__RENDER_EXPOSURE__ ?? null, frame: e.time.frame,
          hud: false, actors: false, weapon: shot.weapon || 'hidden' };
      }, { shot, settle: report.settle_frames });
      if (errors.length) throw new Error(errors.join('\n'));
      await page.screenshot({ path: join(output, `${shot.id}.png`) });
      const hash = createHash('sha256').update(await readFile(join(output, `${shot.id}.png`))).digest('hex');
      report.shots[shot.id] = { status: 'captured', image: `${shot.id}.png`, sha256: hash, ...state };
      console.log('CAPTURE', shot.id, 'frame', state.frame);
      await writeFile(join(output, 'manifest.json'), JSON.stringify(report, null, 2) + '\n');
    } finally { await page.close(); }
  }
} finally {
  if (browser) await browser.close();
  server.kill();
  await writeFile(join(output, 'manifest.json'), JSON.stringify(report, null, 2) + '\n');
}
console.log('REFERENCE', output);
