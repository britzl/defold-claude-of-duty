import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { captureRequest, selectShots, validateAppliedState } from '../tools/reference_contract.mjs';

const catalog = JSON.parse(execFileSync('lua', ['tools/export_parity.lua', 'catalog']));
const shot = id => catalog.shots.find(s => s.id === id);

test('production catalogue has unique, validated camera requests and explicit unsupported fixtures', () => {
  const selected = selectShots(catalog);
  assert.equal(new Set(selected.map(s => s.id)).size, selected.length);
  const pending = selected.filter(s => captureRequest(s).status === 'pending').map(s => s.id);
  assert.deepEqual(pending.sort(), ['combat_effects','combat_glass','foliage_back','foliage_local','foliage_shadow','glass','local_lights','material_foliage','material_foliage_far','material_foliage_grazing','shadow_cutout','weapon_fire']);
  assert.throws(() => selectShots(catalog, 'street,missing'), /Unknown shot/);
  assert.throws(() => selectShots(catalog, 'street,street'), /Duplicate/);
});

test('night, sunset, clear sky and non-rifle poses survive reference defaults', () => {
  assert.equal(captureRequest(shot('sky_night')).hour, 1.5);
  assert.equal(captureRequest(shot('sky_sunset')).hour, 19.2);
  assert.equal(captureRequest(shot('window_shafts')).clouds, false);
  assert.equal(captureRequest(shot('moon')).clouds, false);
  assert.deepEqual(captureRequest(shot('smg_ads')), {
    status: 'supported', hour: 16.5, clouds: true, weapon: 'smg', pose: 'ads', laboratory: false });
  assert.equal(captureRequest(shot('pistol_hip')).weapon, 'pistol');
  assert.equal(captureRequest(shot('laboratory')).laboratory, true);
});

test('bad camera/time/weapon metadata cannot silently fall back', () => {
  assert.throws(() => captureRequest({ ...shot('street'), fov: NaN }), /Invalid camera/);
  assert.throws(() => captureRequest({ ...shot('street'), lighting: 'missing' }), /Invalid lighting/);
  assert.throws(() => captureRequest({ ...shot('weapon'), weapon_id: 'missing' }), /Unknown weapon/);
});

test('applied-state validation permits rounding but rejects wrong time, weapon, FOV and framebuffer', () => {
  const s = shot('sunset'), request = captureRequest(s);
  const state = { hour: 19.200000000000003, weapon_id: null, deterministic: true,
    camera: { vertical_fov: 65 }, gpu: { width: 1280, height: 720 } };
  assert.doesNotThrow(() => validateAppliedState(state, s, request, catalog));
  for (const patch of [{hour: 16.5}, {hour: NaN}, {weapon_id: 'rifle'}, {deterministic: false},
      {camera: {vertical_fov: 75}}, {gpu: {width: 640, height: 360}}])
    assert.throws(() => validateAppliedState({...state, ...patch}, s, request, catalog), /differs/);
});

test('laboratory export carries production triangles, material assignments and roughness rows', () => {
  const fixture = JSON.parse(execFileSync('lua', ['tools/export_parity.lua', 'laboratory'], { maxBuffer: 16 * 1024 * 1024 }));
  assert.equal(fixture.batches.length, 35);
  assert.equal(fixture.batches.reduce((n,b) => n + b.positions.length / 3, 0), 31926);
  for (const b of fixture.batches) {
    assert.equal(b.positions.length, b.normals.length);
    assert.equal(b.positions.length % 9, 0);
    assert.ok(b.positions.every(Number.isFinite));
    assert.ok(b.material || b.surface || b.glass);
  }
  assert.ok(fixture.batches.some(b => b.surface && b.surface[3] === 1));
});
