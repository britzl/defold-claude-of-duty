// Pure request validation; unsupported fixtures must never be labelled captured.
export const hours = { daylight: 16.5, sunset: 19.2, night: 1.5 };
export function captureRequest(shot) {
  if (!shot.id || !Array.isArray(shot.position) || !Array.isArray(shot.target)
      || shot.position.length !== 3 || shot.target.length !== 3
      || ![...shot.position, ...shot.target, shot.fov].every(Number.isFinite)
      || shot.fov <= 0 || shot.fov >= 180) throw new Error(`Invalid camera: ${shot.id}`);
  if (shot.unsupported) return { status: 'pending', reason: shot.unsupported };
  if (shot.id.includes('foliage'))
    return { status: 'pending', reason: 'Reference foliage UV/coverage and matched shadow fixtures are not qualified.' };
  if (shot.combat_fixture || shot.firing)
    return { status: 'pending', reason: 'Reference transient fixture/event timeline is not implemented.' };
  if (['shadow_cutout', 'local_lights', 'glass'].includes(shot.id))
    return { status: 'pending', reason: 'Geometry is exported, but equivalent cutout/local-light/glass fixture shading is not qualified.' };
  const hour = shot.requested_hour ?? hours[shot.lighting ?? 'daylight'];
  if (!Number.isFinite(hour) || hour < 0 || hour >= 24) throw new Error(`Invalid lighting: ${shot.id}`);
  const weapon = shot.weapon ? shot.weapon_id ?? 'rifle' : null;
  if (weapon && !['rifle', 'smg', 'pistol'].includes(weapon)) throw new Error(`Unknown weapon: ${weapon}`);
  return { status: 'supported', hour, clouds: shot.clouds !== false, weapon,
    pose: shot.weapon === 'ads' ? 'ads' : 'idle', laboratory: !!shot.laboratory };
}
export function selectShots(catalog, requested) {
  const ids = requested ? requested.split(',') : catalog.shots.map(s => s.id);
  if (new Set(ids).size !== ids.length) throw new Error('Duplicate shot selection');
  return ids.map(id => {
    const shot = catalog.shots.find(s => s.id === id);
    if (!shot) throw new Error(`Unknown shot: ${id}`);
    return shot;
  });
}
export function validateAppliedState(state, shot, request, dimensions) {
  const close = (a, b) => Number.isFinite(a) && Math.abs(a - b) < 1e-9;
  if (!close(state.hour, request.hour) || state.weapon_id !== request.weapon || !state.deterministic
      || !close(state.camera?.vertical_fov, shot.fov)
      || state.gpu?.width !== dimensions.width || state.gpu?.height !== dimensions.height)
    throw new Error(`Applied state differs from request for ${shot.id}: ${JSON.stringify({
      hour: state.hour, weapon: state.weapon_id, deterministic: state.deterministic,
      fov: state.camera?.vertical_fov, width: state.gpu?.width, height: state.gpu?.height })}`);
}
