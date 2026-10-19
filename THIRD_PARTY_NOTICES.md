# Third-party notices

The soldier variants, proportions, equipment, weapon sockets and animation
layers in `game/ai/variants.lua`, `geometry.lua`, `rig.lua` and `animation.lua`
adapt Claude-of-Duty's `src/ai/soldier.js`, `weapon.js`, `rig.js`, `clips.js`
and `animator.js` under the licence below. Static-ground contact anchors, the
rigid Lua IK evaluator, variant-scaled collision boxes and physics-frame mapping
are Defold adaptations.

The weapon dimensions, arm lengths, grip frames, finger curls and animation
tuning in `game/weapons/geometry.lua`, `arms.lua`, `motion.lua` and `clips.lua`
adapt Claude-of-Duty's `src/weapons/models/*.js`, `hands.js`, `viewmodel.js` and
`clips.js` under the licence below. The bounded Lua recipes, rigid-joint arm
shader, fixed-tick motion, exact ADS constraint and connected-wrist IK are
Defold adaptations.

`render/agx.glsl` adapts the neutral AgX implementation in
Claude-of-Duty's `src/render/glsl.js`, also used by the Kaigen reference.

`render/surface_noise.glsl`, the nineteen recipes and microdetail in
`render/surfaces.glsl`, and the layering in `render/weathering.glsl` adapt
`src/materials/glsl/noise.js`, `surfaces-arch.js`, `surfaces-ground.js`,
`surfaces-metal.js`, `surfaces-organic.js`, `generator.js` and `shader.js` from the
same project. The Kaigen reference uses the same recipes. Adaptations include
integer periodic lattices, wrapped board/coating/thread IDs, resolution-dependent
noise filtering, defined descending ramps, linear data storage and geometry-anchored
weathering/masks. All source attribution remains under the following licence.

The coarse interior footprint gate in `render/lighting.glsl` and
`game/world/interior.lua` adapts the approach in `src/render/materialpatch.js`
and `src/render/index.js` from the same MIT-licensed project. The doorway and
awning extensions, environment filtering and BRDF integration are local implementations.

The cascade sphere fitting, overlapping transitions and contact-hardening shadow
approach in `game/render/shadows.lua` and `render/shadows.glsl` adapt
`src/render/csm.js` from the same project. The Defold atlas layout, packed-depth
sampling, fixed bilinear comparison kernel and shared procedural cutout coverage
are local adaptations.

The visibility-arc integration and short sun-ray march in `render/occlusion.fp`
adapt `src/render/gtao.js` and `src/render/contact.js` from the same project.
The packed depth/normal prepass, fixed spatial samples, bilateral upsampling and
material-cavity combination are local adaptations; no temporal history is used.

The celestial positions, atmospheric medium and scattering, cloud decks, noise,
and volumetric integration in `game/render/daylight.lua` and `render/atmosphere*`,
`render/clouds.glsl`, `render/sky*` and `render/fog*` adapt `src/sky/atmosphere.js`,
`celestial.js`, `clouds.js`, `noise.js` and `volumetrics.js` from that project.
The fixed presets, reduced integration budgets, sky lookup and Defold shadow/depth
reconstruction are local adaptations. Multiple scattering is approximated.

The generated colour-grade transform in `render/grade.fp`, luminance sharpening,
lens shading and grain in `render/composite.fp`, and the metering, bloom and ADS
focus rules in `render/exposure.fp`, `render/bloom.fp` and `render/lens.fp` adapt
`src/render/lut.js`, `composite.js`, `exposure.js`, `bloom.js` and `dof.js` from
that project. Portable packed exposure, the 2D LUT layout, bounded blur and the
Defold scheduling/resource tiers are local adaptations.

The building footprints, setback depths, room programmes, gate design and
set-piece locations in `game/world/layout.lua`, `architecture.lua`, `interior.lua`
and `dressing.lua` adapt `src/world/layout.js`, `buildings.js`, `interiors.js`,
`kit.js` and `dressing.js` from the same project. The bounded Lua geometry kit,
shared collision/navigation descriptions, route-safe placement changes, mesh
batching and reduced tessellation are local implementations.

The ragdoll mass proportions, joint swing/twist ranges and settling policy in
`game/physics/rig.lua` and `game/physics/defold.lua` adapt the humanoid specification
and sleep rules in `src/physics/ragdoll.js`. The 18-body Bullet articulation,
box proxies, native body pooling, skeleton mapping and lifecycle are local
implementations; the reference PBD solver is not copied.

MIT License

Copyright (c) 2026 mshumer

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
