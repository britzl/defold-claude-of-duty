# Third-party notices

`render/agx.glsl` adapts the neutral AgX implementation in
Claude-of-Duty's `src/render/glsl.js`, also used by the Kaigen reference.

`render/surface_noise.glsl` and the plaster, concrete, asphalt and wood recipes
in `render/surfaces.glsl` adapt `src/materials/glsl/noise.js`, `surfaces-arch.js`,
`surfaces-ground.js` and `surfaces-organic.js` from the same project. The Kaigen
reference uses the same recipes. Adaptations include integer periodic lattices,
wrapped board/coating IDs, band-limited noise and defined descending ramps.

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
