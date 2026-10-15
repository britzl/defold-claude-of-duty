// Runs inside the reference page; geometry comes from Defold's actual fixture.
export async function installLaboratory(fixture) {
  const THREE = await import('/node_modules/three/build/three.module.js');
  const e = window.__ENGINE__, world = e.ctx.get('world'), materials = e.ctx.get('materials');
  const root = new THREE.Group();
  root.name = 'parity-laboratory';
  root.matrixAutoUpdate = false;
  root.matrix.copy(world.A.xform);
  world.root.visible = false;
  const aliases = { plaster_sand: 'plaster', plaster_cream: 'plaster', trim: 'plaster',
    metal: 'metal_brushed', awning_red: 'fabric' };
  let meshes = 0, vertices = 0;
  for (const b of fixture.batches) {
    // Special light/glass/cutout shots stay pending until their paths agree.
    if (b.glass || b.key === 'cutout') continue;
    const geometry = new THREE.BufferGeometry();
    geometry.setAttribute('position', new THREE.Float32BufferAttribute(b.positions, 3));
    geometry.setAttribute('normal', new THREE.Float32BufferAttribute(b.normals, 3));
    geometry.setAttribute('uv', new THREE.Float32BufferAttribute(new Float32Array(b.positions.length / 3 * 2), 2));
    let material;
    if (b.surface) {
      material = new THREE.MeshStandardMaterial({ color: new THREE.Color(.65,.65,.65),
        roughness: b.surface[2], metalness: b.surface[3] });
    } else {
      const name = aliases[b.material] ?? b.material;
      if (!materials.names().includes(name)) throw new Error(`Missing reference material: ${name}`);
      // Both use their production recipe. Tint/recipe differences stay visible.
      material = materials.get(name, { uvMode: 'triplanar', vertexMasks: false });
    }
    const mesh = new THREE.Mesh(geometry, material);
    mesh.name = `parity/${b.key}`;
    mesh.castShadow = mesh.receiveShadow = true;
    geometry.computeBoundingSphere();
    root.add(mesh); meshes++; vertices += b.positions.length / 3;
  }
  e.scene.add(root);
  root.updateMatrixWorld(true);
  return { version: fixture.version, meshes, vertices,
    geometry: 'Production Defold fixture triangles transformed into reference level space',
    shading: 'Reference production recipes; tint/weathering/interior lighting are not normalized',
    exclusions: ['glass panes', 'perforated panel', 'local-light fixture qualification'] };
}
