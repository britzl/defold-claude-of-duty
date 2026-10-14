// Reference recipes adapted for deterministic, periodic Defold GPU baking.
// Copyright (c) 2026 mshumer, MIT; see THIRD_PARTY_NOTICES.md.
#include "/render/surface_noise.glsl"
float surface_ramp(float a,float b,float x) { return a<b?smoothstep(a,b,x):1.0-smoothstep(b,a,x); }


void plaster_surface(vec2 uv, out vec3 alb, out float h, out float rough, out float metal, out float ao){
  const vec2 P = vec2(8.0);
  vec2 p = uv * P + 5.0 * 5.3;

  // trowel: broad sweeps, anisotropic, with a fine skim on top
  vec2 sw = owShear(p * 1.5, 1.0, 3.0);
  float trowel = owFbm01(sw, owShearPer(P * 1.5, 3.0), 5, 0.55);
  float skim   = owFbm01(p * 12.0, P * 12.0, 5, 0.5);
  float micro  = owFbm01(p * 24.0, P * 24.0, 3, 0.5);
  float macro  = owFbm01(p * 0.6, P * 0.6, 3, 0.6);

  vec3 cBase = owSRGB(vec3(0.598, 0.578, 0.538));
  vec3 cWarm = owSRGB(vec3(0.512, 0.462, 0.395));
  vec3 cGrey = owSRGB(vec3(0.382, 0.378, 0.372));
  vec3 c = mix(cBase, cWarm, surface_ramp(0.3, 0.8, macro));
  c *= 0.94 + 0.12 * skim;
  c = mix(c, cGrey, surface_ramp(0.45, 0.95, trowel) * 0.42);
  c = mix(c, cBase * 1.10, surface_ramp(0.55, 0.15, trowel) * 0.30);

  h = 0.70 + (trowel - 0.5) * 0.10 + (skim - 0.5) * 0.030 + (micro - 0.5) * 0.012;
  rough = 0.80 + (skim - 0.5) * 0.12 - surface_ramp(0.5, 0.9, trowel) * 0.10;
  ao = 1.0;
  metal = 0.0;

  // ---- skim-coat laps ------------------------------------------------------
  // A plasterer works the wall in ~40 cm passes, and every pass sets a hair
  // lighter or darker than the one before with a faint arris where the trowel
  // lifted off. This is the mid-frequency signal that separates plaster from
  // paint at 2-5 m — without it the wall is one value plus a sprinkle of specks.
  vec2 lapUv = owShear(p * 0.75, 1.0, 1.0);
  float lapF = lapUv.y + owFbm01(p * 1.1, P * 1.1, 3, 0.6) * 1.4;
  float lapI = floor(lapF);
  float lapT = fract(lapF);
  float lapR = owHash11(mod(lapI,6.0) * 1.71 + 5.0 * 2.3);
  c *= 0.885 + 0.240 * lapR;
  rough += (lapR - 0.5) * 0.10;

  /**
   * THE 0.1-1 m BAND. A wall seen from 2-3 m fills the frame with about half a
   * metre of itself, which is a hole in the frequency budget: the macro layer
   * varies over 4-12 m and the detail map over 10 mm, so between them the
   * surface has nothing and measures a standard deviation of 5 over a
   * 260x240 patch — a flat colour with a sprinkle of specks. These three
   * bands (damp bloom, hand-height soiling, and a soft dirt wash) sit at
   * 15-90 cm and are what actually makes a plastered wall read as plaster.
   */
  // NB the contrast expansion. A 4-octave fbm01 spans about 0.3-0.7, never
  // 0-1, so writing 0.86 + 0.30 * n gives a +/-6% wash and not the +/-20%
  // the numbers suggest — the same trap the macro layer documents. Every band
  // here is re-centred and expanded before it is used.
  float dampB = owFbm01(owWarp(p * 1.6 + 3.7, P * 1.6, 0.7, 3), P * 1.6, 4, 0.58);
  dampB = clamp((dampB - 0.5) * 2.6 + 0.5, 0.0, 1.0);
  c *= 0.80 + 0.42 * dampB;
  rough += (dampB - 0.5) * 0.12;
  float soil2 = owFbm01(owWarp(p * 3.4 + 21.0, P * 3.4, 0.55, 3), P * 3.4, 4, 0.55);
  soil2 = clamp((soil2 - 0.5) * 2.4 + 0.5, 0.0, 1.0);
  c *= 0.875 + 0.26 * soil2;
  float wash = owFbm01(p * 8.0 + 6.0, P * 8.0, 4, 0.5);
  wash = clamp((wash - 0.5) * 2.2 + 0.5, 0.0, 1.0);
  c *= 0.925 + 0.155 * wash;
  float lapEdge = (1.0 - surface_ramp(0.0, 0.05, lapT)) * (0.35 + 0.65 * lapR);
  h += lapEdge * 0.022 - (lapR - 0.5) * 0.014;
  c *= 1.0 + lapEdge * 0.07;

  // ---- sand tooth: the 0.5-2 mm grain of the finish coat, with a matching
  //      height channel. Without this the wall is paint, not plaster.
  // 6-9 mm float grain. The finer 1-2 mm tooth is the shared detail map's
  // job: at 2.2 m over 1024 texels one texel is 2.1 mm, so anything past
  // K = 22 here is a sub-texel hash that bakes as dither and mips to grey.
  vec4 tooth = owWorley(p * 20.0, P * 20.0, 1.0);
  float grain = surface_ramp(0.46, 0.06, tooth.x);
  float grainSel = 0.40 + 0.60 * step(0.32, tooth.z);
  h += grain * grainSel * 0.030;
  ao -= grain * 0.07;
  c *= 1.0 + (grain * grainSel - 0.20) * 0.16;
  rough += (tooth.z - 0.5) * 0.11 + grain * 0.05;
  // dust and shadow sit in the troughs between grains
  float trough = surface_ramp(0.52, 0.86, tooth.x);
  c = mix(c, c * 0.84, trough * 0.40);

  // pinholes from the float
  vec4 ph = owWorley(p * 22.0, P * 22.0, 1.0);
  float hole = surface_ramp(0.24, 0.0, ph.x) * step(0.80, ph.w);
  h -= hole * 0.06;
  ao -= hole * 0.4;

  // hairline crazing — a fine, wide-spread net
  float hair = owCracks(p * 9.0, P * 9.0, 0.9, 0.016, 0.52);
  hair += owCracks(p * 16.0 + 6.0, P * 16.0, 0.95, 0.015, 0.62) * 0.5;
  hair = clamp(hair, 0.0, 1.0);
  h -= hair * 0.030;
  ao -= hair * 0.18;
  c = mix(c, c * 0.80, hair * 0.45);

  // structural cracks — few, wide, branching
  float crack = owCracks(p * 4.5 + 17.0, P * 4.5, 0.8, 0.018, 0.62);
  h -= crack * 0.16;
  ao -= crack * 0.6;
  c = mix(c, owSRGB(vec3(0.300, 0.278, 0.250)), crack * 0.8);

  // blown plaster: patches spalled off, revealing render/brick beneath
  float blowMask = owFbm01(owWarp(p * 1.05 + 9.0, P * 1.05, 1.1, 3), P * 1.05, 4, 0.55);
  float blow = surface_ramp(0.775, 0.845, blowMask);
  float blowEdge = surface_ramp(0.745, 0.790, blowMask) - blow;
  vec3 substrate = mix(owSRGB(vec3(0.360, 0.245, 0.195)), owSRGB(vec3(0.430, 0.400, 0.360)),
                       owFbm01(p * 9.0, P * 9.0, 4, 0.5));
  substrate *= 0.85 + 0.3 * owFbm01(p * 20.0, P * 20.0, 3, 0.5);
  c = mix(c, substrate, blow * 0.85);
  h -= blow * 0.13;
  ao -= blow * 0.26;
  rough += blow * 0.10;
  // the lip of the blown patch is bright and sharp
  c += blowEdge * 0.06;
  h += blowEdge * 0.02;

  // ---- chipped patches: 6-9 cm flakes knocked off the skim, showing the darker
  //      browncoat. Deliberately FEWER and LARGER than a fine speckle: a dense
  //      sprinkle of 3 cm dark dots on a facade reads as fly dirt, not as damage,
  //      and it is the one thing that survives at every distance and so gives the
  //      whole wall a screen-space texture.
  vec4 ck = owWorley(owWarp(p * 4.2 + 13.0, P * 4.2, 0.6, 3), P * 4.2, 0.95);
  float ckSel = step(0.930, ck.w);
  float ckSize = 0.22 + 0.20 * ck.z;
  float ckShape = surface_ramp(ckSize, ckSize * 0.3,
                             ck.x * (0.70 + 0.60 * owFbm01(p * 16.0, P * 16.0, 3, 0.5)));
  float chip = ckSel * ckShape;
  // The browncoat is the same family as the finish, just darker and coarser —
  // a chip is a shallow flake, not a hole punched in the wall.
  vec3 coat = mix(c, owSRGB(vec3(0.392, 0.336, 0.284)), 0.52);
  coat *= 0.90 + 0.20 * owFbm01(p * 18.0, P * 18.0, 3, 0.5);
  c = mix(c, coat, chip * 0.58);
  h -= chip * 0.05;
  ao -= chip * 0.26;
  rough += chip * 0.09;
  float ckLip = max(ckSel * (surface_ramp(ckSize * 1.25, ckSize, ck.x) - ckShape), 0.0);
  c *= 1.0 + ckLip * 0.10;
  h += ckLip * 0.010;

  // water staining: tide marks and slow brown bleed
  float stain = owFbm01(vec2(p.x * 1.6, p.y * 3.2), vec2(P.x * 1.6, P.y * 3.0), 5, 0.6);
  float tide = surface_ramp(0.60, 0.78, stain) * (1.0 - surface_ramp(0.78, 0.94, stain));
  c = mix(c, owSRGB(vec3(0.400, 0.330, 0.245)), tide * 0.45);
  c *= 1.0 - surface_ramp(0.50, 0.95, stain) * 0.34;
  rough += tide * 0.05;

  // black mould in the damp corners
  float mould = surface_ramp(0.72, 0.95, owFbm01(p * 4.0 + 25.0, P * 4.0, 5, 0.6)) *
                surface_ramp(0.45, 0.8, stain);
  c = mix(c, owSRGB(vec3(0.085, 0.090, 0.080)), mould * 0.7);
  rough += mould * 0.08;

  // grime in recesses
  float cavity = 1.0 - surface_ramp(0.48, 0.72, h);
  c = mix(c, owSRGB(vec3(0.22, 0.21, 0.19)), cavity * 0.30);

  alb = clamp(c, vec3(0.02), vec3(0.88));
  rough = clamp(rough, 0.35, 0.99);
  ao = clamp(ao, 0.15, 1.0);
  h = clamp(h, 0.0, 1.0);
}


void concrete_surface(vec2 uv, float floor_variant, out vec3 alb, out float h, out float rough, out float metal, out float ao){
  const vec2 P = vec2(8.0);
  float seed=mix(11.0,47.0,floor_variant);
  vec2 p = uv * P + seed * 13.7;

  // ---- base tone: pour variation, wet/dry patches, cement bloom ----
  float macro = owFbm01(p * 0.5, P * 0.5, 4, 0.58);
  float mid   = owFbm01(owWarp(p * 2.0, P * 2.0, 0.7, 3), P * 2.0, 5, 0.5);
  float fine  = owFbm01(p * 18.0, P * 18.0, 4, 0.5);
  float micro = owFbm01(p * 26.0, P * 26.0, 3, 0.5);

  vec3 cLight = owSRGB(vec3(0.520, 0.512, 0.492));
  vec3 cMid   = owSRGB(vec3(0.395, 0.392, 0.385));
  vec3 cDark  = owSRGB(vec3(0.255, 0.253, 0.258));
  vec3 c = mix(cMid, cLight, surface_ramp(0.35, 0.85, macro));
  c = mix(c, cDark, surface_ramp(0.55, 0.95, mid) * 0.55);
  c *= 0.93 + 0.14 * fine;
  // The 0.1-1 m band — see the long note in PLASTER. Pour blotching and the
  // wash of dirt that runs over any concrete left outdoors.
  // contrast-expanded: see the note in PLASTER
  float pourB = owFbm01(owWarp(p * 1.5 + 8.3, P * 1.5, 0.6, 3), P * 1.5, 4, 0.58);
  pourB = clamp((pourB - 0.5) * 2.5 + 0.5, 0.0, 1.0);
  c *= 0.82 + 0.38 * pourB;
  float wash = owFbm01(p * 7.0 + 2.0, P * 7.0, 4, 0.5);
  wash = clamp((wash - 0.5) * 2.2 + 0.5, 0.0, 1.0);
  c *= 0.925 + 0.155 * wash;

  h = 0.62 + (fine - 0.5) * 0.035 + (mid - 0.5) * 0.05;
  rough = 0.70 + (mid - 0.5) * 0.16 + (micro - 0.5) * 0.07;
  ao = 1.0;
  metal = 0.0;

  // ---- exposed aggregate: stone chips sitting just under the skin ----
  vec4 agg = owWorley(p * 13.0, P * 13.0, 0.95);
  float aggShape = surface_ramp(0.46, 0.10, agg.x);
  float aggRnd = agg.z;
  // Only some chips break the surface.
  float aggExposed = aggShape * step(0.74, owFbm01(p * 3.0 + 5.0, P * 3.0, 3, 0.5) + aggRnd * 0.35);
  h += aggExposed * 0.022 * (0.5 + aggRnd);
  c = mix(c, mix(owSRGB(vec3(0.335, 0.320, 0.300)), owSRGB(vec3(0.560, 0.545, 0.505)), aggRnd), aggExposed * 0.7);
  rough += aggExposed * 0.07 * (aggRnd - 0.5);

  // ---- coarse sand fraction: the 5-8 mm grit of the cement skin ----
  // The 0.5-2 mm tooth is NOT authored here. At 2.5 m over a 1024 bake one
  // texel is 2.4 mm, so a 1 mm grain is a sub-texel hash: it bakes as white
  // noise, dithers at mip 0 and is gone by mip 1. That band belongs to the
  // shared detail map, which is tiled ten times finer. What lives here is the
  // grit you can actually resolve, at real amplitude.
  vec4 sand = owWorley(p * 20.0, P * 20.0, 1.0);
  float sandM = surface_ramp(0.44, 0.05, sand.x);
  float sandSel = 0.40 + 0.60 * step(0.30, sand.z);
  h += sandM * sandSel * 0.028;
  c *= 1.0 + (sandM * sandSel - 0.20) * 0.15;
  rough += (sand.z - 0.5) * 0.11 + sandM * 0.04;
  ao -= sandM * 0.06;
  float sandTrough = surface_ramp(0.52, 0.88, sand.x);
  c = mix(c, c * 0.86, sandTrough * 0.34);

  // ---- air pockets / bug holes from the pour ----
  vec4 pores = owWorley(p * 22.0, P * 22.0, 1.0);
  float pore = surface_ramp(0.26, 0.0, pores.x) * step(0.84, pores.w);
  h -= pore * 0.055;
  ao -= pore * 0.55;
  rough += pore * 0.10;

  // 1.0 = board-formed wall (1) vs poured slab (0)
  // 0.0 = saw-cut control joints, for floors
  float formAmt = 1.0-floor_variant;
  float jointAmt = floor_variant;

  // ---- formwork: horizontal board lines + tie-rod holes ----
  float boards = uv.y * 4.0;
  float bi = floor(boards);
  float bf = fract(boards);
  float seam = (1.0 - surface_ramp(0.0, 0.030, bf)) + (1.0 - surface_ramp(0.0, 0.030, 1.0 - bf));
  seam = clamp(seam, 0.0, 1.0);
  // Boards are never perfectly aligned: each course steps a fraction of a mm.
  float boardStep = (owHash11(mod(bi,4.0) + seed) - 0.5) * 0.028 * formAmt;
  h += boardStep;
  h -= seam * 0.055 * formAmt;
  ao -= seam * 0.40 * formAmt;
  c *= 1.0 - seam * 0.16 * formAmt;
  // cement bled along the seam and set lighter
  float bleed = (1.0 - surface_ramp(0.0, 0.10, abs(bf - 0.02))) * 0.5 * formAmt;
  c = mix(c, cLight * 1.05, bleed * 0.35 * owFbm01(p * 8.0, P * 8.0, 3, 0.5));

  // tie holes, plugged, one every other board
  vec2 tf = fract(vec2(uv.x * 3.0, boards * 0.5)) - 0.5;
  float tieRnd = owHash12(mod(floor(vec2(uv.x * 3.0, boards * 0.5)),vec2(3.0,2.0)) + seed);
  float tie = surface_ramp(0.085, 0.05, length(tf * vec2(1.0, 2.0))) * step(0.45, tieRnd) * formAmt;
  h -= tie * 0.10;
  ao -= tie * 0.5;
  c = mix(c, cDark * 0.85, tie * 0.6);

  // ---- saw-cut control joints (slabs) + power-float polish ----
  vec2 jd = abs(fract(uv + 0.5) - 0.5);
  float joint = max(1.0 - surface_ramp(0.0035, 0.010, jd.x), 1.0 - surface_ramp(0.0035, 0.010, jd.y));
  joint *= jointAmt;
  h -= joint * 0.10;
  ao -= joint * 0.55;
  c = mix(c, cDark * 0.62, joint * 0.65);
  // trowel arcs left by the power float
  float swirl = owFbm01(owWarp(p * 1.1 + 3.0, P * 1.1, 1.4, 3), P * 1.1, 3, 0.6);
  rough -= jointAmt * surface_ramp(0.35, 0.85, swirl) * 0.10;
  c *= 1.0 - jointAmt * surface_ramp(0.4, 0.9, swirl) * 0.07;

  // ---- structural cracks: branch from the seams and corners ----
  float crk = owCracks(p * 2.6, P * 2.6, 0.85, 0.028, 0.50);
  float crkFine = owCracks(p * 7.0 + 31.0, P * 7.0, 0.9, 0.020, 0.60) * 0.55;
  float crack = clamp(crk + crkFine, 0.0, 1.0);
  h -= crack * 0.12;
  ao -= crack * 0.45;
  c = mix(c, cDark * 0.80, crack * 0.42);
  rough += crack * 0.12;

  // ---- spalling: a chunk of the skin has broken off, aggregate showing ----
  vec4 sp = owWorley(p * 1.1 + 7.3, P * 1.1, 0.9);
  float spallCell = step(0.90, sp.w);
  float spall = spallCell * surface_ramp(0.44, 0.16, sp.x) *
                surface_ramp(0.42, 0.62, owFbm01(p * 4.0 + 2.0, P * 4.0, 4, 0.5));
  h -= spall * 0.13;
  ao -= spall * 0.35;
  c = mix(c, mix(cDark, cMid, aggRnd) * 0.88, spall * 0.8);
  rough += spall * 0.10;
  // rim of the spall catches light
  float spallRim = spall * (1.0 - spall) * 4.0;
  c *= 1.0 + spallRim * 0.10;

  // ---- small chips: 2-5 cm bites out of the skin showing darker, wetter
  //      concrete plus the sand fraction underneath (~3% of the surface) ----
  vec4 ck = owWorley(owWarp(p * 5.6 + 19.0, P * 5.6, 0.6, 3), P * 5.6, 0.95);
  float ckSel = step(0.90, ck.w);
  float ckSize = 0.20 + 0.16 * ck.z;
  float ckShape = surface_ramp(ckSize, ckSize * 0.3,
                             ck.x * (0.72 + 0.56 * owFbm01(p * 16.0, P * 16.0, 3, 0.5)));
  float chip = ckSel * ckShape;
  c = mix(c, mix(c * 0.74, mix(cDark, cMid, sand.z), 0.5), chip * 0.85);
  h -= chip * 0.045;
  ao -= chip * 0.24;
  rough += chip * 0.08;
  float ckLip = max(ckSel * (surface_ramp(ckSize * 1.25, ckSize, ck.x) - ckShape), 0.0);
  c *= 1.0 + ckLip * 0.10;

  // ---- staining: rain runoff, soot, rust bleed from rebar ----
  // Only ~3:1 stretched and shallow: the long runs come from the runtime
  // weather layer, which knows where the sills and ledges are. A 10:1 stretch
  // baked into the tile at full strength just reads as wood veneer.
  float streak = owFbm01(vec2(p.x * 6.0, p.y * 2.0), vec2(P.x * 6.0, P.y * 2.0), 5, 0.55);
  float runoff = surface_ramp(0.58, 0.95, streak) * (0.35 + 0.65 * surface_ramp(0.2, 0.8, macro));
  c *= 1.0 - runoff * 0.14;
  rough += runoff * 0.05;

  float rustBleed = surface_ramp(0.72, 0.98, streak * (0.6 + 0.5 * tieRnd)) * step(0.80, tieRnd);
  c = mix(c, owSRGB(vec3(0.42, 0.24, 0.12)), rustBleed * 0.45);

  // dirt collects in every recess
  float cavity = 1.0 - surface_ramp(0.42, 0.66, h);
  c = mix(c, owSRGB(vec3(0.20, 0.19, 0.17)), cavity * 0.35);

  alb = clamp(c, vec3(0.02), vec3(0.85));
  rough = clamp(rough, 0.48, 0.98);
  ao = clamp(ao, 0.15, 1.0);
  h = clamp(h, 0.0, 1.0);
}


void asphalt_surface(vec2 uv, out vec3 alb, out float h, out float rough, out float metal, out float ao){
  const vec2 P = vec2(8.0);
  vec2 p = uv * P + 71.0 * 6.9;

  // ---- binder: dark, slightly blue-grey, sun-bleached in patches ----
  float macro = owFbm01(p * 0.5, P * 0.5, 4, 0.6);
  float mid   = owFbm01(p * 3.0, P * 3.0, 5, 0.5);
  float fine  = owFbm01(p * 16.0, P * 16.0, 4, 0.5);

  vec3 cFresh = owSRGB(vec3(0.115, 0.115, 0.122));
  vec3 cWorn  = owSRGB(vec3(0.300, 0.298, 0.295));
  vec3 c = mix(cFresh, cWorn, surface_ramp(0.25, 0.85, macro) * 0.85);
  // Half the old fine-grain albedo contrast: the stone read belongs in the
  // height/normal channels, not in a high-frequency albedo dither.
  c *= 0.94 + 0.12 * fine;

  h = 0.60 + (mid - 0.5) * 0.06;
  rough = 0.78 + (mid - 0.5) * 0.10 + (fine - 0.5) * 0.14;
  metal = 0.0;
  ao = 1.0;

  // ---- aggregate: dense angular chippings, three grades ----
  // Angularity comes from warping the worley domain: round cells become
  // faceted, which is what separates asphalt from a pebble beach.
  vec2 ap = owWarp(p, P, 0.10, 3);
  vec4 big = owWorley(ap * 12.0, P * 12.0, 1.0);
  float bigM = surface_ramp(0.40, 0.16, big.x);
  float bigExposed = bigM * surface_ramp(0.30, 0.62, owFbm01(p * 2.2 + 3.0, P * 2.0, 4, 0.5) + big.w * 0.5);
  vec4 small = owWorley(ap * 22.0 + 7.0, P * 22.0, 1.0);
  float smallM = surface_ramp(0.36, 0.10, small.x);
  float smallExposed = smallM * step(0.30, small.w);
  vec4 grit = owWorley(ap * 28.0 + 3.0, P * 28.0, 1.0);
  float gritM = surface_ramp(0.32, 0.06, grit.x) * step(0.45, grit.z);

  vec3 stoneA = owSRGB(vec3(0.400, 0.392, 0.378));
  vec3 stoneB = owSRGB(vec3(0.210, 0.200, 0.192));
  vec3 stoneC = owSRGB(vec3(0.560, 0.520, 0.470));
  vec3 stone = mix(stoneA, stoneB, big.z);
  stone = mix(stone, stoneC, step(0.90, big.w));

  // Stones are read by their relief and their specular, not by their tint:
  // colour contrast is roughly halved and the height contribution raised.
  c = mix(c, stone, bigExposed * 0.52);
  c = mix(c, mix(stoneA, stoneC, small.z), smallExposed * 0.22);
  c = mix(c, mix(stoneB, stoneA, grit.z), gritM * 0.14);
  h += bigExposed * 0.15 * (0.6 + 0.6 * big.z) + smallExposed * 0.065 + gritM * 0.022;
  rough += bigExposed * (0.10 - 0.22 * big.z) + smallExposed * (0.06 - 0.14 * small.z);

  // voids between the aggregate — where the binder has ravelled out
  float voidM = surface_ramp(0.50, 0.85, big.x) * surface_ramp(0.28, 0.6, small.x);
  h -= voidM * 0.10;
  ao -= voidM * 0.14;

  // ---- tyre polish: two smooth bands where wheels track ----
  float lane = abs(fract(uv.x * 1.0 + 0.25) - 0.5) * 2.0;
  float polish = (1.0 - surface_ramp(0.10, 0.62, lane)) *
                 surface_ramp(0.25, 0.65, owFbm01(vec2(p.x * 0.7, p.y * 5.0), vec2(P.x, P.y * 5.0), 4, 0.5));
  rough -= polish * 0.16;
  h -= polish * 0.012;
  c = mix(c, c * 0.78 + owSRGB(vec3(0.045, 0.045, 0.048)), polish * 0.45);

  // ---- patch repairs: darker rectangles-ish with a seam ----
  vec4 rep = owWorley(owWarp(p * 0.5 + 13.0, P * 0.5, 1.6, 3), P * 0.5, 0.9);
  float inPatch = step(0.72, rep.w);
  float patchEdge = (1.0 - surface_ramp(0.0, 0.06, rep.y - rep.x)) * inPatch;
  c = mix(c, cFresh * (0.85 + 0.35 * fine), inPatch * 0.20);
  rough = mix(rough, 0.84, inPatch * 0.22);
  h -= patchEdge * 0.07;
  ao -= patchEdge * 0.20;
  c = mix(c, cFresh * 0.5, patchEdge * 0.35);
  // tar bleeding out of the seam, glossy
  float tar = patchEdge * surface_ramp(0.4, 0.7, owFbm01(p * 6.0, P * 6.0, 3, 0.5));
  rough -= tar * 0.35;
  c = mix(c, owSRGB(vec3(0.055, 0.055, 0.058)), tar * 0.7);

  // ---- alligator cracking + long thermal cracks ----
  float gator = owCracks(p * 3.4, P * 3.4, 0.9, 0.032, 0.56);
  float thermal = owCracks(p * 0.9 + 41.0, P * 0.9, 0.75, 0.05, 0.70);
  float crack = clamp(gator + thermal, 0.0, 1.0);
  h -= crack * 0.16;
  ao -= crack * 0.30;
  c = mix(c, owSRGB(vec3(0.045, 0.043, 0.042)), crack * 0.85);
  rough += crack * 0.12;

  // ---- oil stains, dark and slightly glossy ----
  float oil = surface_ramp(0.68, 0.90, owFbm01(owWarp(p * 1.8 + 31.0, P * 1.8, 0.9, 3), P * 1.8, 4, 0.55));
  c = mix(c, owSRGB(vec3(0.045, 0.043, 0.046)), oil * 0.6);
  rough -= oil * 0.16;

  // ---- dust settled in the low spots ----
  float dust = surface_ramp(0.55, 0.30, h) * surface_ramp(0.35, 0.75, macro);
  c = mix(c, owSRGB(vec3(0.420, 0.390, 0.340)), dust * 0.35);
  rough += dust * 0.10;

  alb = clamp(c, vec3(0.02), vec3(0.75));
  rough = clamp(rough, 0.44, 0.99);
  // see the AO note in GRAVEL: on a ground plane this channel is the shading
  ao = clamp(ao, 0.68, 1.0);
  h = clamp(h, 0.0, 1.0);
}


void wood_surface(vec2 uv, out vec3 alb, out float h, out float rough, out float metal, out float ao){
  const vec2 P = vec2(8.0);
  const float PLANKS = 5.0;
  vec2 p = uv * P + 19.0 * 12.9;

  // ---- plank layout: rows running along X, staggered butt joints ----
  float rowF = uv.y * PLANKS;
  float row = mod(floor(rowF), PLANKS);
  float rf = fract(rowF);
  float stagger = owHash11(row + 19.0 * 2.0);
  float lenF = uv.x * 2.0 + stagger;             // 2 boards per row lengthwise
  float board = floor(lenF);
  float lf = fract(lenF);
  vec4 rnd = owHash42(vec2(mod(board,2.0), row) + 19.0);

  // gaps between boards
  const float GY = 0.035, GX = 0.010;
  float ey = min(surface_ramp(0.0, GY, rf), surface_ramp(0.0, GY, 1.0 - rf));
  float ex = min(surface_ramp(0.0, GX, lf), surface_ramp(0.0, GX, 1.0 - lf));
  float face = min(ex, ey);

  // ---- grain: rings stretched along the board, warped, with knots ----
  vec2 gp = vec2(lf * 2.0 + rnd.x * 13.0, rf + rnd.y * 7.0);
  vec2 GP = vec2(16.0, 8.0);
  float warp = owFbm(vec2(gp.x * 3.0, gp.y * 12.0), vec2(GP.x * 3.0, GP.y * 12.0), 4, 0.55);
  float ringCoord = gp.y * (14.0 + rnd.z * 12.0) + warp * 2.2 + rnd.w * 5.0;

  // knots pull the rings into a tight radial swirl
  vec2 knotP = vec2(0.25 + rnd.x * 0.5, 0.35 + rnd.y * 0.3);
  float kd = length((vec2(lf, rf) - knotP) * vec2(2.2, 1.0));
  float hasKnot = step(0.68, rnd.z);
  float knotPull = hasKnot * exp(-kd * 9.0);
  ringCoord = mix(ringCoord, kd * 42.0, clamp(knotPull * 1.6, 0.0, 1.0));

  float rings = fract(ringCoord);
  float ringDark = surface_ramp(0.42, 0.5, rings) * (1.0 - surface_ramp(0.5, 0.62, rings));
  float latewood = surface_ramp(0.30, 0.52, rings);

  // fine fibre along the grain
  float fibre = owFbm01(owShear(p * 6.0, 0.0, 40.0), owShearPer(P * 6.0, 40.0), 4, 0.5);
  float micro = owFbm01(p * 22.0, P * 22.0, 3, 0.5);

  // ---- colour ----
  vec3 wLight = owSRGB(vec3(0.505, 0.408, 0.290));
  vec3 wMid   = owSRGB(vec3(0.362, 0.272, 0.180));
  vec3 wDark  = owSRGB(vec3(0.205, 0.142, 0.092));
  vec3 wGrey  = owSRGB(vec3(0.372, 0.355, 0.328));   // weathered silver-grey
  vec3 c = mix(wLight, wMid, rnd.w * 0.8 + latewood * 0.5);
  c = mix(c, wDark, ringDark * 0.65);
  c *= 0.90 + 0.18 * fibre;
  c = mix(c, wDark * 0.7, clamp(knotPull * 2.2, 0.0, 1.0) * 0.8);

  // weathering: UV-bleached, silvered, worst on the exposed boards
  float weather = surface_ramp(0.20, 0.85, owFbm01(p * 0.8, P * 0.8, 3, 0.6)) * (0.4 + 0.6 * rnd.x);
  c = mix(c, wGrey, weather * 0.68);

  float faceH = 0.74 - ringDark * 0.02 - latewood * 0.012 + (fibre - 0.5) * 0.03 + (micro - 0.5) * 0.008;
  faceH += (rnd.y - 0.5) * 0.035;              // boards cup and sit at different heights
  faceH -= clamp(knotPull * 1.5, 0.0, 1.0) * 0.03;

  // splits and checks running along the grain
  float split = owScratches(vec2(p.x, p.y) * 2.0, P * 2.0, 30.0, 0.0, 0.66) * weather;
  faceH -= split * 0.10;
  c = mix(c, wDark * 0.45, split * 0.7);

  // saw marks across the board
  float saw = owFbm01(owShear(p * 3.0, 0.0, 1.0) * vec2(30.0, 1.0), vec2(P.x * 90.0, P.y * 3.0), 3, 0.5);
  faceH += (saw - 0.5) * 0.012;

  // rounded / bashed board edges
  float edgeD = min(min(rf, 1.0 - rf) / GY, min(lf, 1.0 - lf) / GX);
  float bevel = 1.0 - surface_ramp(0.0, 2.4, edgeD);
  faceH -= bevel * 0.035;
  c *= 1.0 - bevel * 0.10;
  c = mix(c, wLight * 1.15, bevel * surface_ramp(0.5, 0.9, owFbm01(p * 20.0, P * 20.0, 3, 0.5)) * 0.35);

  // ---- gap between boards: dark, deep ----
  float m = surface_ramp(0.05, 0.7, face);
  h = mix(0.44, faceH, m);
  c = mix(wDark * 0.25, c, m);
  rough = mix(0.95, 0.62 + 0.22 * fibre + weather * 0.20 + split * 0.15, m);
  ao = mix(0.25, 1.0, surface_ramp(0.0, 0.5, face)) - bevel * 0.12 * m;
  metal = 0.0;

  // ---- nails ----
  vec2 nf = vec2(fract(lf * 3.0 + 0.5) - 0.5, (rf - 0.5));
  float nd = length(nf * vec2(3.0, 1.0) / vec2(3.0, 1.0) * vec2(1.0, 1.0));
  nd = length(vec2(fract(lf * 3.0 + 0.5) - 0.5, rf - 0.22) * vec2(1.4, 1.0));
  float nail = surface_ramp(0.055, 0.030, nd) * m * step(0.3, rnd.w);
  h -= nail * 0.02;
  c = mix(c, owSRGB(vec3(0.230, 0.200, 0.170)), nail * 0.85);
  rough = mix(rough, 0.55, nail);
  metal = mix(metal, 0.85, nail * 0.7);
  ao -= nail * 0.25;
  // rust weep under the nail
  float weep = surface_ramp(0.11, 0.05, nd) * step(0.3, rnd.w) * surface_ramp(0.0, 0.6, rf - 0.22) * m;
  c = mix(c, owSRGB(vec3(0.330, 0.185, 0.095)), clamp(weep, 0.0, 1.0) * 0.4);

  // grime
  float cavity = 1.0 - surface_ramp(0.55, 0.78, h);
  c = mix(c, owSRGB(vec3(0.120, 0.106, 0.088)), cavity * 0.45);
  // ground-in dirt over the whole board
  float soil = surface_ramp(0.40, 0.88, owFbm01(owWarp(p * 2.2 + 5.0, P * 2.2, 0.9, 3), P * 2.2, 5, 0.6));
  c = mix(c, owSRGB(vec3(0.185, 0.160, 0.128)), soil * 0.40);
  rough += soil * 0.08;

  alb = clamp(c, vec3(0.02), vec3(0.80));
  rough = clamp(rough, 0.25, 0.99);
  ao = clamp(ao, 0.12, 1.0);
  h = clamp(h, 0.0, 1.0);
}

// Bounded adaptations of the reference surface recipes: plaster mottling,
// asphalt aggregate, wood fibres, worn metal and woven cloth. Periodic noise
// keeps opposite edges continuous; frequencies stay below the bake's Nyquist.
float surface_hash(vec2 p) { return owHash12(p); }

vec3 owRustColour(float t, float grain){
  // young rust is orange, mature rust is dark red-brown, old rust is near-black
  vec3 c1 = owSRGB(vec3(0.560, 0.290, 0.110));   // fresh orange
  vec3 c2 = owSRGB(vec3(0.380, 0.180, 0.085));   // mid
  vec3 c3 = owSRGB(vec3(0.190, 0.100, 0.060));   // mature
  vec3 c4 = owSRGB(vec3(0.640, 0.400, 0.190));   // powdery bloom
  vec3 c = mix(c1, c2, surface_ramp(0.15, 0.6, t));
  c = mix(c, c3, surface_ramp(0.55, 1.0, t));
  c = mix(c, c4, surface_ramp(0.55, 0.95, grain) * 0.45);
  return c * (0.82 + 0.36 * grain);
}


void metal_brushed_surface(vec2 uv, out vec3 alb, out float h, out float rough, out float metal, out float ao){
  const vec2 P = vec2(8.0);
  vec2 p = uv * P + 83.0 * 15.1;

  // brushing runs along X: heavy shear so the noise stretches into fibres
  vec2 bp = owShear(p, 0.0, 64.0);
  vec2 BP = owShearPer(P, 64.0);
  float brush1 = owFbm01(bp * 2.0, BP * 2.0, 4, 0.5);
  float brush2 = owFbm01(bp * 8.0 + 3.0, BP * 8.0, 3, 0.5);
  float brush3 = owFbm01(owShear(p * 4.0, 0.0, 24.0), owShearPer(P * 4.0, 24.0), 3, 0.5);
  float brush = brush1 * 0.5 + brush2 * 0.32 + brush3 * 0.18;

  float macro = owFbm01(p * 0.9, P * 0.9, 3, 0.6);

  vec3 c = owSRGB(vec3(0.560, 0.565, 0.575));
  c *= 0.93 + 0.13 * brush;
  c *= 0.97 + 0.06 * macro;

  metal = 1.0;
  rough = 0.22 + brush * 0.24 + (macro - 0.5) * 0.06;
  h = 0.78 + (brush - 0.5) * 0.012;
  ao = 1.0;

  // deeper score lines
  float score = owScratches(p * 1.0, P, 40.0, 0.0, 0.60);
  rough += score * 0.22;
  h -= score * 0.006;
  c *= 1.0 - score * 0.05;

  // cross scratches from handling
  float cross = owScratches(p * 3.0, P * 3.0, 8.0, 3.0, 0.70) * 0.7;
  rough += cross * 0.20;
  h -= cross * 0.004;

  // dents: shallow, wide, they break the reflection
  float dent = owFbm01(p * 3.0 + 7.0, P * 3.0, 3, 0.6);
  h += (dent - 0.5) * 0.05;

  // fingerprints and grease smudges — the thing that sells brushed metal
  float smudge = surface_ramp(0.58, 0.86, owFbm01(owWarp(p * 2.2 + 19.0, P * 2.2, 0.7, 3), P * 2.2, 4, 0.55));
  rough += smudge * 0.22;
  c *= 1.0 - smudge * 0.06;
  metal -= smudge * 0.10;

  // grime settling in
  float grime = surface_ramp(0.66, 0.95, owFbm01(p * 5.0, P * 5.0, 4, 0.55));
  c = mix(c, owSRGB(vec3(0.180, 0.175, 0.165)), grime * 0.35);
  rough += grime * 0.18;
  metal -= grime * 0.35;

  alb = clamp(c, vec3(0.02), vec3(0.88));
  rough = clamp(rough, 0.08, 0.95);
  metal = clamp(metal, 0.0, 1.0);
  ao = clamp(ao, 0.4, 1.0);
  h = clamp(h, 0.0, 1.0);
}


void fabric_surface(vec2 uv, out vec3 alb, out float h, out float rough, out float metal, out float ao){
  const vec2 P = vec2(8.0);
  const float THREADS = 96.0;
  vec2 p = uv * P + 43.0 * 3.9;

  // ---- plain weave: warp over weft on alternating cells ----
  vec2 t = uv * THREADS;
  vec2 cell = floor(t);
  vec2 f = fract(t) - 0.5;
  float over = mod(cell.x + cell.y, 2.0);   // 0 -> warp on top, 1 -> weft on top

  float warpProfile = cos(f.x * 3.14159) ;
  float weftProfile = cos(f.y * 3.14159);
  float top = mix(warpProfile, weftProfile, over);
  float bot = mix(weftProfile, warpProfile, over) * 0.45;
  float weave = max(top, bot);
  float threadId = owHash12(mod(cell,vec2(THREADS)) + 43.0);

  // ---- fuzz and slubs ----
  float fuzz = owFbm01(p * 12.0, P * 12.0, 3, 0.55);
  float slub = owFbm01(p * 14.0, P * 14.0, 4, 0.5);
  float macro = owFbm01(p * 1.2, P * 1.2, 4, 0.6);

  vec3 cA = vec3(0.72);
  vec3 cB = vec3(0.48);
  vec3 c = mix(cA, cB, threadId * 0.6 + slub * 0.4);
  c *= 0.865 + 0.215 * (weave * 0.5 + 0.5);
  c *= 0.960 + 0.075 * fuzz;
  c *= 0.90 + 0.20 * macro;

  h = 0.55 + weave * 0.30 + (fuzz - 0.5) * 0.03 + (slub - 0.5) * 0.05;
  rough = 0.86 + (1.0 - weave) * 0.08 + (fuzz - 0.5) * 0.06;
  metal = 0.0;
  ao = mix(0.82, 1.0, surface_ramp(-0.4, 0.9, weave));

  // ---- drape folds ---------------------------------------------------------
  // Cloth under tension gathers into soft parallel ridges roughly a hand's width
  // apart, wandering as they run. At the 0.26 m mapping the awnings use, 2.6
  // cycles across the tile is a ~10 cm fold. A weave alone reads as printed
  // canvas; the fold field is what gives a canopy its shape between its poles.
  float foldC = uv.y * 3.0 + uv.x + owFbm01(p * 0.9, P * 0.9, 3, 0.62) * 2.2;
  float foldT = abs(fract(foldC) - 0.5) * 2.0;          // 0 at crest, 1 in trough
  float crest = 1.0 - foldT;
  float foldR = owHash11(mod(floor(foldC),1.0) * 2.13 + 43.0);
  float fold = crest * crest * (0.55 + 0.75 * foldR);
  h += (fold - 0.30) * 0.115;
  c *= 0.895 + 0.21 * fold;
  ao -= (1.0 - crest) * 0.14;
  // the crease line itself is polished by handling and holds the dust
  float creaseLine = 1.0 - surface_ramp(0.0, 0.10, foldT);
  rough -= creaseLine * 0.06;
  c *= 1.0 + creaseLine * 0.05;

  // ---- wear: threadbare patches, fraying, pulled threads ----
  float wearField = surface_ramp(0.58, 0.82, owFbm01(owWarp(p * 2.0, P * 2.0, 0.8, 3), P * 2.0, 4, 0.55));
  c = mix(c, c * 1.35 + 0.02, wearField * 0.5);
  rough += wearField * 0.06;
  h -= wearField * 0.05;

  float pulled = owScratches(p * 3.0, P * 3.0, 18.0, 1.0, 0.68);
  h += pulled * 0.05;
  c *= 1.0 - pulled * 0.10;

  // ---- stains and dust ----
  float stain = surface_ramp(0.55, 0.9, owFbm01(owWarp(p * 1.5 + 7.0, P * 1.5, 1.0, 3), P * 1.5, 5, 0.6));
  c = mix(c, c * 0.42 + owSRGB(vec3(0.09, 0.08, 0.06)), stain * 0.55);
  rough += stain * 0.05;

  float dust = surface_ramp(0.4, 0.85, owFbm01(p * 6.0, P * 6.0, 4, 0.5));
  c = mix(c, owSRGB(vec3(0.400, 0.375, 0.335)), dust * 0.14);

  alb = clamp(c, vec3(0.02), vec3(0.85));
  rough = clamp(rough, 0.5, 0.99);
  ao = clamp(ao, 0.25, 1.0);
  h = clamp(h, 0.0, 1.0);
}


void brick_surface(vec2 uv, out vec3 alb, out float h, out float rough, out float metal, out float ao){
  const vec2 P = vec2(8.0);
  const float COLS = 6.0;     // bricks across the tile
  const float ROWS = 18.0;    // courses up the tile
  vec2 p = uv * P + 23.0 * 9.1;

  // ---------------- brick lattice, running bond ----------------
  float rowF = uv.y * ROWS;
  float row = floor(rowF);
  float colF = uv.x * COLS + mod(row, 2.0) * 0.5;
  float col = floor(colF);
  vec2 id = vec2(mod(col, COLS), mod(row, ROWS));
  vec2 f = vec2(fract(colF), fract(rowF));

  vec4 rnd = owHash42(id + 23.0 * 3.0);
  vec4 rnd2 = owHash42(id * 1.37 + 21.0 + 23.0);
  vec4 rnd3 = owHash42(id * 0.73 + 7.7 + 23.0 * 1.9);

  // Bricks are laid by hand: each one is a hair off square.
  vec2 jitter = (rnd.xy - 0.5) * vec2(0.012, 0.030);
  vec2 fj = f + jitter;

  // joint thickness (10mm of a 225mm x 75mm course). The joint is *raked*: a
  // flat mortar bed with a hard arris at the brick edge. Ramping across the
  // whole joint width is what makes mortar read as a painted line.
  const float JX = 0.048, JY = 0.135;
  float dxj = min(fj.x, 1.0 - fj.x);
  float dyj = min(fj.y, 1.0 - fj.y);
  float shoulder = 0.74 + 0.16 * rnd3.w;    // some joints struck flush, some sharp
  float ex = surface_ramp(JX * shoulder, JX * 1.02, dxj);
  float ey = surface_ramp(JY * shoulder, JY * 1.02, dyj);
  float face = min(ex, ey);                 // 1 = brick face, 0 = mortar

  // per-brick surface coords so the face texture never repeats
  vec2 bp = vec2(fj.x, fj.y) * vec2(3.0, 1.0) + rnd.zw * 17.0;
  vec2 BP = vec2(24.0);

  // ---------------- mortar ----------------
  float mSand = owFbm01(p * 20.0, P * 20.0, 4, 0.5);
  vec4 mGrain = owWorley(p * 24.0, P * 24.0, 1.0);
  float mortarRough = owFbm01(p * 20.0, P * 20.0, 4, 0.55);
  vec3 mortarCol = mix(owSRGB(vec3(0.400, 0.388, 0.362)), owSRGB(vec3(0.278, 0.272, 0.260)),
                       surface_ramp(0.3, 0.8, mortarRough));
  mortarCol *= 0.84 + 0.32 * mSand;
  mortarCol *= 0.88 + 0.24 * owFbm01(p * 6.0, P * 6.0, 4, 0.6);
  mortarCol = mix(mortarCol, owSRGB(vec3(0.235, 0.228, 0.215)), surface_ramp(0.5, 0.06, mGrain.x) * 0.40);
  mortarCol = mix(mortarCol, owSRGB(vec3(0.520, 0.505, 0.470)), surface_ramp(0.30, 0.02, owWorley(p * 25.0 + 4.0, P * 25.0, 1.0).x) * 0.35);

  // some joints are struck flush, some are raked deep, some crumbled out.
  // 0.10-0.15 of a 0.055 m relief = 5-8 mm of real recess.
  float jointDepth = 0.10 + 0.05 * owFbm01(p * 1.2, P * 1.2, 3, 0.5);
  float crumble = surface_ramp(0.62, 0.86, owFbm01(p * 9.0 + 4.0, P * 9.0, 4, 0.5));
  jointDepth += crumble * 0.09;
  // the mortar bed itself is not flat — it holds the trowel's sand texture
  float mortarH = -(mSand - 0.5) * 0.018 - surface_ramp(0.5, 0.0, mGrain.x) * 0.012;

  // ---------------- brick face ----------------
  float faceN = owFbm01(bp * 2.2, BP, 5, 0.5);
  float faceFine = owFbm01(bp * 5.0, BP * 2.0, 4, 0.5);
  vec4 facePore = owWorley(bp * 7.0, BP * 3.5, 1.0);
  // Pits cluster instead of forming an even dot grid, and their size varies.
  float poreCluster = surface_ramp(0.42, 0.78, owFbm01(bp * 3.0 + 8.0, BP * 1.5, 4, 0.55));
  float pore = surface_ramp(0.26 + 0.16 * facePore.z, 0.0, facePore.x) * step(0.55, facePore.w) * poreCluster;

  // Colour families: red stock, dark burnt header, pale sand-lime, brown.
  vec3 cA = owSRGB(vec3(0.430, 0.238, 0.183));   // red stock
  vec3 cB = owSRGB(vec3(0.318, 0.183, 0.150));   // deep red
  vec3 cC = owSRGB(vec3(0.196, 0.132, 0.120));   // burnt header
  vec3 cD = owSRGB(vec3(0.492, 0.392, 0.300));   // sandy
  vec3 cE = owSRGB(vec3(0.372, 0.288, 0.218));   // brown

  vec3 brick = mix(cA, cB, rnd.z);
  brick = mix(brick, cC, step(0.90, rnd.w) * 0.70);
  brick = mix(brick, cD, step(0.94, rnd2.x) * 0.62);
  brick = mix(brick, cE, step(0.55, rnd2.y) * 0.50);
  // every brick came out of the kiln a different shade: +/-12% per brick
  brick *= 0.88 + 0.24 * rnd3.x;
  // within-brick banding from the extrusion
  brick *= 0.86 + 0.28 * faceN;
  // fine sand grain across the face — this is what reads at 0.5 m
  // bp is per-brick, and a brick is only ~170 texels wide, so bp*26 was 78
  // cycles across it — 2.2 texels a cycle. This is the band that has to still
  // be there at 0.5 m, so it is authored at 7 texels and given more contrast.
  float faceGrain = owFbm01(bp * 8.0, BP * 4.0, 4, 0.55);
  brick *= 0.87 + 0.26 * faceGrain;
  brick = mix(brick, brick * 1.22, surface_ramp(0.55, 0.9, faceFine) * 0.5);
  // dark iron spots and sand inclusions
  brick = mix(brick, brick * 0.62, pore * 0.85);
  brick = mix(brick, brick * 0.72, surface_ramp(0.34, 0.0, facePore.x) * step(0.86, facePore.z));
  brick = mix(brick, owSRGB(vec3(0.62, 0.58, 0.50)), surface_ramp(0.86, 0.98, faceFine) * 0.35);

  float faceH = 0.72 + (faceN - 0.5) * 0.05 + (faceFine - 0.5) * 0.025
              + (rnd2.z - 0.5) * 0.05;               // each brick sits proud/shy
  faceH -= pore * 0.075;

  // Broken arrises: ~5% of the edge length is knocked off, deep enough to
  // catch a shadow, showing pale raw clay under the fired skin.
  float edgeD = min(dxj / JX, dyj / JY);
  float chipNoise = owFbm01(bp * 6.0 + 3.0, BP * 3.0, 4, 0.5);
  float chip = surface_ramp(1.7, 0.30, edgeD) * surface_ramp(0.60, 0.80, chipNoise) * step(0.66, rnd3.z);
  faceH -= chip * 0.17;
  brick = mix(brick, brick * 0.72 + owSRGB(vec3(0.20, 0.13, 0.09)), chip * 0.65);

  // ---------------- combine face + mortar ----------------
  // face is already a shaped profile, so no second smoothstep here: that is
  // what used to smear the arris across the full joint width.
  float m = face;
  h = mix(0.72 - jointDepth + mortarH, faceH, m);
  vec3 c = mix(mortarCol, brick, m);
  // every brick came out of the kiln with a slightly different skin
  float brickRough = 0.58 + 0.32 * rnd2.z + (rnd3.y - 0.5) * 0.20;
  rough = mix(0.88 + 0.10 * mSand + 0.06 * (mortarRough - 0.5),
              brickRough + 0.14 * faceN + 0.10 * (faceGrain - 0.5) + chip * 0.14, m);
  ao = mix(0.34, 1.0, surface_ramp(0.0, 0.75, face));
  ao -= chip * 0.30;
  metal = 0.0;

  // mortar smeared over the brick edge by the trowel
  float smear = surface_ramp(0.5, 1.0, 1.0 - face) * surface_ramp(0.55, 0.9, owFbm01(p * 14.0, P * 14.0, 4, 0.5));
  c = mix(c, mortarCol * 1.05, smear * 0.5);

  // ---------------- weathering over the whole wall ----------------
  // The 0.1-1 m band — see the long note in PLASTER.
  float soilB = owFbm01(owWarp(p * 1.8 + 27.0, P * 1.8, 0.6, 3), P * 1.8, 4, 0.58);
  soilB = clamp((soilB - 0.5) * 2.5 + 0.5, 0.0, 1.0);
  c *= 0.845 + 0.33 * soilB;

  // efflorescence: salt bloom, strongest around joints
  float efflo = surface_ramp(0.62, 0.96, owFbm01(owWarp(p * 2.6, P * 2.6, 0.8, 3), P * 2.6, 4, 0.5));
  efflo *= mix(1.0, 0.35, m);
  c = mix(c, owSRGB(vec3(0.66, 0.652, 0.632)), efflo * 0.5);
  rough += efflo * 0.10;

  // soot / rain runoff — short, shallow and only ~3:1 stretched; the long runs
  // are added at runtime where a real ledge sheds water.
  float streak = owFbm01(vec2(p.x * 7.0, p.y * 2.3), vec2(P.x * 7.0, P.y * 2.0), 5, 0.55);
  float runoff = surface_ramp(0.50, 0.92, streak);
  c *= 1.0 - runoff * 0.16;

  // hairline cracks stepping through the joints
  float crack = owCracks(p * 2.2, P * 2.2, 0.85, 0.038, 0.58);
  h -= crack * 0.10;
  ao -= crack * 0.45;
  c = mix(c, c * 0.35, crack * 0.7);

  // dirt in every crevice
  float cavity = 1.0 - surface_ramp(0.50, 0.74, h);
  c = mix(c, owSRGB(vec3(0.16, 0.15, 0.14)), cavity * 0.32);

  alb = clamp(c, vec3(0.02), vec3(0.85));
  rough = clamp(rough, 0.35, 0.99);
  ao = clamp(ao, 0.12, 1.0);
  h = clamp(h, 0.0, 1.0);
}


void tile_surface(vec2 uv, out vec3 alb, out float h, out float rough, out float metal, out float ao){
  const vec2 P = vec2(8.0);
  const float N = 6.0;
  vec2 p = uv * P + 31.0 * 4.4;

  vec2 tp = uv * N;
  vec2 id = mod(floor(tp),vec2(N));
  vec2 f = fract(tp);
  vec4 rnd = owHash42(id + 31.0);

  // Flat grout bed with a hard arris at the tile edge: a full-width ramp is
  // what makes a joint read as a drawn line instead of a recess.
  const float J = 0.045;
  float dxj = min(f.x, 1.0 - f.x);
  float dyj = min(f.y, 1.0 - f.y);
  float ex = surface_ramp(J * 0.70, J * 1.02, dxj);
  float ey = surface_ramp(J * 0.70, J * 1.02, dyj);
  float face = min(ex, ey);

  float glaze = owFbm01(f * 6.0 + rnd.xy * 21.0, vec2(48.0), 4, 0.5);
  vec3 cTile = mix(owSRGB(vec3(0.700, 0.690, 0.660)), owSRGB(vec3(0.470, 0.500, 0.505)), rnd.z * 0.7);
  cTile *= 0.93 + 0.13 * glaze;
  cTile *= 0.92 + 0.16 * rnd.y;                                 // per-tile batch shade

  float grout = owFbm01(p * 20.0, P * 20.0, 4, 0.5);
  vec3 cGrout = owSRGB(vec3(0.400, 0.385, 0.360)) * (0.85 + 0.3 * grout);
  cGrout = mix(cGrout, owSRGB(vec3(0.13, 0.13, 0.12)), 0.45);   // grout is always filthy

  float m = face;
  // 0.06 of a 0.03 m relief = 1.8 mm of grout recess.
  h = mix(0.76 - (grout - 0.5) * 0.02, 0.82 + (rnd.w - 0.5) * 0.04, m);
  vec3 c = mix(cGrout, cTile, m);
  // glazed tile has to stay glossy enough to actually catch a highlight
  rough = mix(0.92, 0.20 + 0.22 * glaze + (rnd.z - 0.5) * 0.14, m);
  ao = mix(0.40, 1.0, surface_ramp(0.0, 0.8, face));
  metal = 0.0;

  // chipped / cracked / missing tiles
  float broken = step(0.90, rnd.x);
  float crack = owCracks(f * 3.0 + rnd.yz * 9.0, vec2(24.0), 0.85, 0.04, 0.45) * m;
  c = mix(c, c * 0.3, crack * 0.8);
  h -= crack * 0.08;
  ao -= crack * 0.5;
  vec3 sub = owSRGB(vec3(0.330, 0.300, 0.270));
  c = mix(c, sub, broken * m * 0.9);
  h -= broken * m * 0.14;
  rough = mix(rough, 0.95, broken * m);

  // scuffs and traffic wear
  float wear = surface_ramp(0.45, 0.95, owFbm01(p * 2.0, P * 2.0, 4, 0.55));
  rough += wear * 0.20 * m;
  c *= 1.0 - wear * 0.12;

  float cavity = 1.0 - surface_ramp(0.68, 0.80, h);
  c = mix(c, owSRGB(vec3(0.14, 0.13, 0.12)), cavity * 0.35);

  alb = clamp(c, vec3(0.02), vec3(0.85));
  rough = clamp(rough, 0.12, 0.95);
  ao = clamp(ao, 0.15, 1.0);
  h = clamp(h, 0.0, 1.0);
}


void dirt_surface(vec2 uv, out vec3 alb, out float h, out float rough, out float metal, out float ao){
  const vec2 P = vec2(8.0);
  vec2 p = uv * P + 13.0 * 3.4;

  float macro = owFbm01(p * 0.6, P * 0.6, 4, 0.62);
  float clump = owBillow(owWarp(p * 3.0, P * 3.0, 0.6, 3), P * 3.0, 5, 0.55);
  float fine  = owFbm01(p * 14.0, P * 14.0, 4, 0.5);
  float micro = owFbm01(p * 22.0, P * 22.0, 3, 0.5);

  vec3 cDry  = owSRGB(vec3(0.430, 0.350, 0.255));
  vec3 cWet  = owSRGB(vec3(0.185, 0.140, 0.100));
  vec3 cPale = owSRGB(vec3(0.560, 0.490, 0.385));
  vec3 c = mix(cDry, cPale, surface_ramp(0.45, 0.9, macro));
  c = mix(c, cWet, surface_ramp(0.55, 0.15, macro) * 0.8);
  // Halved high-frequency albedo contrast; the read moves into height/roughness.
  c *= 0.94 + 0.11 * fine;
  c *= 0.975 + 0.05 * micro;

  h = 0.55 + (macro - 0.5) * 0.14 + (clump - 0.5) * 0.16 + (fine - 0.5) * 0.075;
  rough = 0.88 + (fine - 0.5) * 0.14 + (micro - 0.5) * 0.10;
  metal = 0.0;
  ao = 1.0;

  // dried mud cracks in the flat pans
  float pan = surface_ramp(0.35, 0.65, macro);
  float mud = owCracks(p * 2.4, P * 2.4, 0.85, 0.045, 0.35) * pan;
  h -= mud * 0.16;
  ao -= mud * 0.32;
  c = mix(c, cWet * 0.7, mud * 0.75);
  // the mud plates curl up at their edges
  float plateLift = surface_ramp(0.10, 0.0, mud) * pan;
  h += plateLift * 0.01;

  // stones of two grades
  vec4 st = owWorley(p * 11.0, P * 11.0, 1.0);
  float stone = surface_ramp(0.30, 0.11, st.x) * step(0.62, st.w);
  vec3 scol = mix(owSRGB(vec3(0.330, 0.315, 0.295)), owSRGB(vec3(0.600, 0.575, 0.540)), st.z);
  c = mix(c, scol, stone * 0.6);
  h += stone * 0.085;
  rough = mix(rough, 0.52 + 0.28 * st.z, stone * 0.8);
  ao -= surface_ramp(0.36, 0.28, st.x) * step(0.62, st.w) * 0.10;

  vec4 grit = owWorley(p * 22.0, P * 22.0, 1.0);
  float gritM = surface_ramp(0.26, 0.08, grit.x) * step(0.55, grit.w);
  c = mix(c, mix(scol, cPale, grit.z), gritM * 0.4);
  h += gritM * 0.015;

  // dead grass / organic litter
  float litter = surface_ramp(0.70, 0.86, owFbm01(owShear(p * 8.0, 1.0, 5.0), owShearPer(P * 8.0, 5.0), 4, 0.5));
  litter *= surface_ramp(0.4, 0.8, macro);
  c = mix(c, owSRGB(vec3(0.330, 0.290, 0.160)), litter * 0.5);
  h += litter * 0.012;
  rough += litter * 0.05;

  // sparse moss in the damp low spots
  float moss = surface_ramp(0.74, 0.92, owFbm01(p * 4.5 + 19.0, P * 4.5, 5, 0.6)) * surface_ramp(0.5, 0.1, macro);
  c = mix(c, owSRGB(vec3(0.150, 0.185, 0.105)), moss * 0.65);

  float cavity = 1.0 - surface_ramp(0.40, 0.70, h);
  ao -= cavity * 0.14;

  alb = clamp(c, vec3(0.02), vec3(0.72));
  rough = clamp(rough, 0.45, 0.99);
  ao = clamp(ao, 0.72, 1.0);
  h = clamp(h, 0.0, 1.0);
}


void gravel_surface(vec2 uv, out vec3 alb, out float h, out float rough, out float metal, out float ao){
  const vec2 P = vec2(8.0);
  vec2 p = uv * P + 57.0 * 2.7;

  float bed = owFbm01(p * 1.3, P * 1.3, 4, 0.55);

  /**
   * This is the street. Not a bed of loose chippings — compacted dust and grit
   * with aggregate part-buried in it, which is what a Levantine back street
   * actually is, and much more importantly it is what stops twelve metres of
   * road reading as dither.
   *
   * Two things were wrong before. (1) The finest grade was 208 cells across a
   * 512 bake — 2.5 texels, i.e. white noise, and the "grain" band on top of it
   * was 480 cells across 512, literally sub-texel. (2) The interstitial dust
   * was authored at 0.29 while the stone tops ran to 0.62 and then the runtime
   * cavity-grime layer pushed the (low) bed down another 17% toward black. A
   * 2.5:1 albedo step at a 10 mm period across the whole frame is the textbook
   * recipe for salt-and-pepper. So: three grades at 34/19/9 mm (5.9 texels at
   * the worst), stones separated from the bed by RELIEF and ROUGHNESS rather
   * than by value, and a bed sitting mid-height so the cavity term leaves it
   * alone.
   */
  vec4 a = owWorley(p * 5.5, P * 5.5, 1.0);
  vec4 b = owWorley(p * 10.0 + 5.0, P * 10.0, 1.0);
  vec4 cSm = owWorley(p * 21.0 + 11.0, P * 21.0, 1.0);

  // Sparse: most of what you see is the compacted bed, with stones IN it. The
  // old coverage was ~80% at every grade, which is a shingle beach; a used
  // road shows perhaps a quarter of its aggregate.
  float sA = surface_ramp(0.36, 0.10, a.x) * step(0.44, a.w);
  float sB = surface_ramp(0.30, 0.08, b.x) * step(0.62, b.w);
  float sC = surface_ramp(0.24, 0.06, cSm.x) * step(0.74, cSm.w);

  // The stones live in the height field: raised relief so each one catches the
  // sun on one side and shadows on the other. Half-buried, not tipped out on
  // the surface — the peak-to-trough is only a few mm at world scale.
  float ha = sA * 0.15 * (0.5 + a.z);
  float hb = sB * 0.09 * (0.5 + b.z);
  float hc = sC * 0.025;
  h = 0.54 + (bed - 0.5) * 0.11 + max(max(ha, hb), hc) + 0.22 * (ha + hb);

  /**
   * The stone palette has to straddle the bed value, not sit above it. With
   * the bed at 0.35 and the stones running 0.29-0.51 every dark stone hid in
   * the dust and only the pale ones showed, which is why the road read as
   * white confetti scattered on grey rather than as aggregate. Half the
   * stones are now darker than the bed and half lighter.
   */
  vec3 s1 = owSRGB(vec3(0.372, 0.356, 0.332));
  vec3 s2 = owSRGB(vec3(0.232, 0.220, 0.208));
  vec3 s3 = owSRGB(vec3(0.462, 0.438, 0.400));
  vec3 s4 = owSRGB(vec3(0.352, 0.276, 0.220));
  vec3 top = mix(s1, s2, a.z);
  top = mix(top, s3, step(0.78, a.w));
  top = mix(top, s4, step(0.90, b.w) * 0.7);

  // The bed is dust, and it is only a few percent off the stones sitting in it.
  vec3 cBed = owSRGB(vec3(0.362, 0.336, 0.294));
  vec3 c = mix(cBed, top, clamp(sA * 0.70 + sB * 0.42 + sC * 0.16, 0.0, 1.0));
  // ~9 mm grain, 4.9 texels wide: a texture, not a dither.
  float grain = owFbm01(p * 13.0, P * 13.0, 4, 0.5);
  c *= 0.965 + 0.07 * grain;

  // Per-stone gloss: wet-worn pebbles glint, the dust between them does not.
  // This, not albedo, is what separates a stone from the dust around it.
  // Per-stone gloss, but only a little of it. Under a bright sky the IBL
  // specular lobe is a big part of what a shaded ground plane returns, so a
  // wide roughness spread at the aggregate period is another way of writing
  // salt-and-pepper: clamping this term alone took the measured
  // high-frequency deviation on the road from 2.45 to 1.68.
  rough = 0.82 + 0.05 * grain + (1.0 - clamp(sA + sB, 0.0, 1.0)) * 0.06
        - sA * (0.06 + 0.07 * a.z) - sB * 0.05 * b.z;
  metal = 0.0;
  /**
   * AO IS THE WHOLE BALLGAME ON A GROUND PLANE. A street in shadow is lit
   * almost entirely by the sky, so orm.r is very nearly the only shading
   * term the surface has — a 0.62:1.0 cavity ripple at the 10-30 mm aggregate
   * period is therefore a 1.6:1 luminance ripple at 2 screen pixels, which is
   * precisely the salt-and-pepper the critics measured. (Proved by clamping
   * the albedo to a constant and the normal map to flat: the speckle survived
   * both untouched, and only died when this range was compressed.) Baked
   * cavity AO belongs at low frequency and low contrast; the shading of an
   * individual stone is the normal map's job.
   */
  ao = mix(0.87, 1.0, surface_ramp(0.42, 0.66, h));

  // fine dust filling the gaps
  float dust = 1.0 - surface_ramp(0.44, 0.62, h);
  c = mix(c, cBed * 1.04, dust * 0.5);
  rough += dust * 0.08;
  ao = mix(ao, 1.0, dust * 0.3);

  // Wheel and foot traffic sweeps the loose grit into drifts and polishes bare
  // lanes: 0.5-1.5 m form inside the tile, which is the scale the eye uses to
  // decide whether a road is a surface or a pattern.
  float drift = owFbm01(owWarp(p * 0.9 + 17.0, P * 0.9, 0.8, 3), P * 0.9, 4, 0.6);
  h += (drift - 0.5) * 0.10;
  c *= 0.86 + 0.28 * drift;
  rough += (drift - 0.5) * 0.10;
  // Dust drifts BURY the aggregate: where the drift is deep the stones go
  // under it. Without this the stone density is identical over every square
  // metre of a hundred-metre street, which is the tell that it is a texture.
  c = mix(c, cBed * (0.92 + 0.22 * drift), surface_ramp(0.55, 0.88, drift) * 0.72);

  // Dried tyre tracks and dragged-heel scuffs — long, shallow, low contrast.
  float scuff = owFbm01(owShear(p * 2.2, 0.0, 6.0), owShearPer(P * 2.2, 6.0), 4, 0.5);
  c *= 1.0 - surface_ramp(0.55, 0.92, scuff) * 0.10;
  rough -= surface_ramp(0.6, 0.95, scuff) * 0.08;

  alb = clamp(c, vec3(0.02), vec3(0.78));
  rough = clamp(rough, 0.62, 0.99);
  ao = clamp(ao, 0.72, 1.0);
  h = clamp(h, 0.0, 1.0);
}


void metal_painted_surface(vec2 uv, out vec3 alb, out float h, out float rough, out float metal, out float ao){
  const vec2 P = vec2(8.0);
  vec2 p = uv * P + 61.0 * 11.3;

  // ---- substrate: steel with a mill finish ----
  float mill = owFbm01(owShear(p * 5.0, 1.0, 8.0), owShearPer(P * 5.0, 8.0), 4, 0.5);
  vec3 steel = owSRGB(vec3(0.330, 0.335, 0.345)) * (0.88 + 0.2 * mill);

  // ---- rust that has crept under the paint ----
  float bloom = 1.0 - owBillow(owWarp(p * 1.8, P * 1.8, 1.1, 4), P * 1.8, 5, 0.6);
  float rustField = surface_ramp(0.60, 0.92, bloom);
  float rustGrain = owFbm01(p * 22.0, P * 22.0, 4, 0.55);
  vec3 rustCol = owRustColour(rustField, rustGrain);

  // ---- paint: an industrial coat with roller texture and orange peel ----
  float peel = owFbm01(p * 22.0, P * 22.0, 4, 0.5);
  float roller = owFbm01(owShear(p * 2.0, 0.0, 3.0), owShearPer(P * 2.0, 3.0), 4, 0.5);
  vec3 paint = vec3(0.72) * (0.90 + 0.16 * roller);
  paint *= 0.96 + 0.08 * peel;
  // sun-bleached on the up-facing halves
  float bleach = surface_ramp(0.35, 0.85, owFbm01(p * 0.8, P * 0.8, 3, 0.6));
  paint = mix(paint, paint * 1.25 + 0.03, bleach * 0.5);

  // ---- chipping: paint fails at scratches, impacts and along its own edges ----
  float chipField = owFbm01(owWarp(p * 2.6 + 4.0, P * 2.6, 0.9, 3), P * 2.6, 5, 0.55);
  float chipEdge = owFbm01(p * 12.0, P * 12.0, 4, 0.5);
  // Paint mostly holds: only the top of the distribution actually fails, and
  // it fails hardest where rust is already lifting it from underneath.
  float chipSrc = chipField * 0.60 + chipEdge * 0.20 + rustField * 0.32 + 0.35 * 0.25;
  float chip = surface_ramp(0.66, 0.92, chipSrc);
  // small impact chips scattered around
  vec4 dings = owWorley(p * 20.0, P * 20.0, 1.0);
  float ding = surface_ramp(0.14, 0.03, dings.x) * step(0.88, dings.w);
  chip = clamp(chip + ding, 0.0, 1.0);

  // scratches that cut down to bare metal
  float scr = owScratches(p * 2.5, P * 2.5, 14.0, 1.0, 0.62);
  scr += owScratches(p * 4.0 + 21.0, P * 4.0, 10.0, -1.0, 0.66) * 0.8;
  scr = clamp(scr, 0.0, 1.0);

  // ---- layer stack: paint over primer over rust over steel ----
  vec3 primer = owSRGB(vec3(0.470, 0.300, 0.180));
  float primerBand = surface_ramp(0.0, 0.35, chip) * (1.0 - surface_ramp(0.35, 0.6, chip));

  vec3 c = paint;
  float r = 0.42 + (peel - 0.5) * 0.22 + bleach * 0.16;
  float mtl = 0.0;
  h = 0.74 + (roller - 0.5) * 0.02 + (peel - 0.5) * 0.012;
  ao = 1.0;

  c = mix(c, primer, primerBand * 0.7);
  c = mix(c, rustCol, surface_ramp(0.35, 0.75, chip) * (0.55 + 0.45 * rustField));
  c = mix(c, steel, surface_ramp(0.75, 0.95, chip) * (1.0 - rustField) * 0.9);
  r = mix(r, 0.88, surface_ramp(0.3, 0.8, chip) * (0.4 + 0.6 * rustField));
  r = mix(r, 0.38, surface_ramp(0.8, 1.0, chip) * (1.0 - rustField));
  mtl = mix(0.0, 1.0, surface_ramp(0.78, 0.96, chip) * (1.0 - surface_ramp(0.2, 0.7, rustField)));
  h -= surface_ramp(0.4, 0.8, chip) * 0.16;     // paint has real thickness
  ao -= surface_ramp(0.35, 0.7, chip) * 0.22;
  // the lip of a chip is a bright hard edge
  float lip = surface_ramp(0.30, 0.42, chip) * (1.0 - surface_ramp(0.42, 0.55, chip));
  c *= 1.0 + lip * 0.15;
  h += lip * 0.05;

  // scratches on top of everything
  c = mix(c, owSRGB(vec3(0.500, 0.505, 0.515)), scr * 0.55);
  mtl = mix(mtl, 1.0, scr * 0.6);
  r = mix(r, 0.26, scr * 0.55);

  // ---- dirt and rain streaks ----
  float streak = owFbm01(vec2(p.x * 6.0, p.y * 0.7), vec2(P.x * 6.0, max(P.y, 1.0)), 5, 0.55);
  float grime = surface_ramp(0.52, 0.92, streak);
  c *= 1.0 - grime * 0.30;
  r += grime * 0.10;
  mtl *= 1.0 - grime * 0.5;
  // rust bleed running down from the chips
  float bleed = surface_ramp(0.66, 0.95, streak) * surface_ramp(0.2, 0.6, rustField);
  c = mix(c, owSRGB(vec3(0.360, 0.190, 0.090)), bleed * 0.45);

  float cavity = 1.0 - surface_ramp(0.62, 0.78, h);
  c *= 1.0 - cavity * 0.18;

  alb = clamp(c, vec3(0.02), vec3(0.85));
  rough = clamp(r, 0.14, 0.99);
  metal = clamp(mtl, 0.0, 1.0);
  ao = clamp(ao, 0.2, 1.0);
  h = clamp(h, 0.0, 1.0);
}


void metal_rust_surface(vec2 uv, out vec3 alb, out float h, out float rough, out float metal, out float ao){
  const vec2 P = vec2(8.0);
  vec2 p = uv * P + 37.0 * 7.7;

  // ---- base steel ----
  float mill = owFbm01(owShear(p * 4.0, 1.0, 6.0), owShearPer(P * 4.0, 6.0), 4, 0.5);
  float fine = owFbm01(p * 22.0, P * 22.0, 4, 0.5);
  vec3 steel = owSRGB(vec3(0.330, 0.335, 0.345)) * (0.90 + 0.18 * mill);
  vec3 c = steel;
  h = 0.72 + (mill - 0.5) * 0.02 + (fine - 0.5) * 0.01;
  rough = 0.40 + (mill - 0.5) * 0.16 + (fine - 0.5) * 0.08;
  metal = 1.0;
  ao = 1.0;

  // ---- rust blooms: warped billow clusters, hard-edged where they flake ----
  vec2 wp = owWarp(p * 1.4, P * 1.4, 1.2, 4);
  float bloom = owBillow(wp, P * 1.4, 5, 0.6);
  bloom = 1.0 - bloom;                              // clusters, not veins
  float spread = owFbm01(p * 0.7 + 12.0, P * 0.7, 3, 0.6);
  float rust = surface_ramp(0.36, 0.72, bloom * (0.55 + 0.85 * spread));
  float rustGrain = owFbm01(p * 26.0, P * 26.0, 4, 0.55);
  float pit = owFbm01(p * 24.0, P * 24.0, 3, 0.5);

  // flaking scale: the rust lifts in plates near the edge of a bloom
  float scale = owWorley(p * 16.0, P * 16.0, 1.0).x;
  float flake = surface_ramp(0.30, 0.10, scale) * surface_ramp(0.25, 0.55, rust) * (1.0 - surface_ramp(0.8, 1.0, rust));

  // Rust *colour* is driven by how old the patch is, not by how much of it
  // there is — otherwise every heavily rusted area collapses to the same brown.
  float rustAge = owFbm01(p * 0.85 + 21.0, P * 0.85, 4, 0.62);
  vec3 rustCol = owRustColour(rustAge * 0.8 + rust * 0.3, rustGrain);
  c = mix(c, rustCol, rust);
  metal = mix(1.0, 0.0, surface_ramp(0.15, 0.55, rust));
  rough = mix(rough, 0.86 + 0.10 * rustGrain, surface_ramp(0.1, 0.6, rust));
  h += rust * 0.11 * (0.4 + rustGrain) + flake * 0.13;
  h -= surface_ramp(0.5, 0.95, rust) * pit * 0.14;      // deep pitting under old rust
  ao -= flake * 0.30 + surface_ramp(0.6, 1.0, rust) * 0.15;

  // ---- pitting straight into the steel where rust has eaten through ----
  vec4 pits = owWorley(p * 22.0, P * 22.0, 1.0);
  float deep = surface_ramp(0.22, 0.0, pits.x) * step(0.72, pits.w) * surface_ramp(0.3, 0.8, rust);
  h -= deep * 0.22;
  ao -= deep * 0.45;
  c = mix(c, rustCol * 0.35, deep * 0.7);

  // ---- scratches through everything, exposing bright metal ----
  float scr = owScratches(p * 3.0, P * 3.0, 12.0, 1.0, 0.60);
  scr += owScratches(p * 5.0 + 8.0, P * 5.0, 9.0, -2.0, 0.66) * 0.7;
  scr = clamp(scr, 0.0, 1.0) * 0.6;
  c = mix(c, owSRGB(vec3(0.480, 0.485, 0.495)), scr * 0.8);
  metal = mix(metal, 1.0, scr * 0.85);
  rough = mix(rough, 0.24, scr * 0.7);
  h -= scr * 0.010;

  // ---- grime ----
  float grime = surface_ramp(0.55, 0.9, owFbm01(vec2(p.x * 5.0, p.y * 0.8), vec2(P.x * 5.0, max(P.y, 1.0)), 5, 0.55));
  c *= 1.0 - grime * 0.25;
  rough += grime * 0.08;

  alb = clamp(c, vec3(0.02), vec3(0.80));
  rough = clamp(rough, 0.12, 0.99);
  ao = clamp(ao, 0.15, 1.0);
  h = clamp(h, 0.0, 1.0);
}


void rubber_surface(vec2 uv, out vec3 alb, out float h, out float rough, out float metal, out float ao){
  const vec2 P = vec2(8.0);
  vec2 p = uv * P + 97.0 * 9.6;

  // moulded pebble grain
  vec4 pb = owWorley(p * 12.0, P * 12.0, 1.0);
  float pebble = surface_ramp(0.42, 0.10, pb.x);
  float fine = owFbm01(p * 12.0, P * 12.0, 3, 0.5);
  float macro = owFbm01(p * 1.5, P * 1.5, 4, 0.6);

  h = 0.60 + pebble * 0.10 + (fine - 0.5) * 0.02 + (macro - 0.5) * 0.03;
  // 0.20 sRGB ~= 0.031 linear. Anything darker lands under the 0.02 albedo
  // floor applied below, which clamps the entire surface flat (a black,
  // detail-free rubber that violates the "no flat surfaces" bar).
  vec3 c = owSRGB(vec3(0.200, 0.200, 0.206));
  c *= 0.85 + 0.25 * (pebble * 0.5 + 0.5);
  c *= 0.94 + 0.10 * fine;

  rough = 0.88 - pebble * 0.06 + (fine - 0.5) * 0.08;
  metal = 0.0;
  ao = mix(0.6, 1.0, pebble * 0.5 + 0.5);

  // mould seam
  float seam = 1.0 - surface_ramp(0.0, 0.012, abs(fract(uv.y * 2.0 + 0.5) - 0.5));
  h += seam * 0.03;
  c *= 1.0 + seam * 0.35;
  rough -= seam * 0.10;

  // scuffs: rubber goes chalky-grey where it abrades
  float scuff = surface_ramp(0.55, 0.88, owFbm01(owWarp(p * 3.0, P * 3.0, 0.8, 3), P * 3.0, 4, 0.55));
  c = mix(c, owSRGB(vec3(0.220, 0.218, 0.212)), scuff * 0.45);
  rough += scuff * 0.06;
  h -= scuff * 0.015;

  // cracking from ozone / age
  float crack = owCracks(p * 7.0, P * 7.0, 0.9, 0.028, 0.62);
  h -= crack * 0.06;
  c *= 1.0 - crack * 0.35;
  ao -= crack * 0.35;

  // dust
  float dust = surface_ramp(0.5, 0.9, owFbm01(p * 8.0, P * 8.0, 4, 0.5));
  c = mix(c, owSRGB(vec3(0.290, 0.275, 0.250)), dust * 0.16);

  alb = clamp(c, vec3(0.02), vec3(0.35));
  rough = clamp(rough, 0.55, 0.99);
  ao = clamp(ao, 0.3, 1.0);
  h = clamp(h, 0.0, 1.0);
}


void glass_surface(vec2 uv, out vec3 alb, out float h, out float rough, out float metal, out float ao){
  const vec2 P = vec2(8.0);
  vec2 p = uv * P + 3.0 * 2.2;

  float smear = owFbm01(owShear(p * 3.0, 1.0, 6.0), owShearPer(P * 3.0, 6.0), 4, 0.5);
  float dustF = owFbm01(p * 5.0, P * 5.0, 5, 0.55);
  float spots = owWorley(p * 24.0, P * 24.0, 1.0).x;
  float fine = owFbm01(p * 12.0, P * 12.0, 3, 0.5);

  // glass itself is almost black in albedo; the look comes from reflections
  vec3 c = owSRGB(vec3(0.045, 0.050, 0.052));

  float dirty = surface_ramp(0.45, 0.85, dustF);
  c = mix(c, owSRGB(vec3(0.300, 0.290, 0.265)), dirty * 0.35);

  rough = 0.045 + smear * 0.10 * surface_ramp(0.3, 0.9, dustF) + dirty * 0.22;
  rough += surface_ramp(0.30, 0.05, spots) * 0.25;             // water spots
  rough += (fine - 0.5) * 0.02;

  // fine scratches
  float scr = owScratches(p * 2.0, P * 2.0, 24.0, 1.0, 0.70);
  rough += scr * 0.25;
  c += scr * 0.02;

  h = 0.5 + (smear - 0.5) * 0.004;
  metal = 0.0;
  ao = 1.0 - dirty * 0.1;

  alb = clamp(c, vec3(0.02), vec3(0.5));
  rough = clamp(rough, 0.02, 0.7);
  h = clamp(h, 0.0, 1.0);
}


void detail_surface(vec2 uv, out vec3 alb, out float h, out float rough, out float metal, out float ao){
  const vec2 P = vec2(8.0);
  vec2 p = uv * P + 1.0;
  // ~10 mm swell, ~3.5 mm tooth
  float a = owFbm01(p * 3.0, P * 3.0, 4, 0.55);
  float b = owFbm01(p * 9.0, P * 9.0, 4, 0.52);
  // 3.9 mm pits and 1.6 mm grains — both wide enough to survive two mip levels
  vec4 pores = owWorley(p * 8.0, P * 8.0, 1.0);
  vec4 grit  = owWorley(p * 20.0, P * 20.0, 1.0);
  float scr = owScratches(p * 2.5, P * 2.5, 16.0, 1.0, 0.66)
            + owScratches(p * 4.0 + 5.0, P * 4.0, 11.0, -2.0, 0.70) * 0.8;
  // Proud grains: a solid, rounded bump rather than a threshold speck.
  float gritA = surface_ramp(0.34, 0.08, pores.x) * step(0.38, pores.z);
  float gritB = surface_ramp(0.30, 0.06, grit.x) * step(0.34, grit.z);
  float pit   = surface_ramp(0.26, 0.0, pores.x) * step(0.72, pores.w);
  h = 0.5 + (a - 0.5) * 0.34 + (b - 0.5) * 0.26;
  h -= pit * 0.38;
  h += gritA * 0.26 * (0.5 + grit.z) + gritB * 0.20;
  h -= clamp(scr, 0.0, 1.0) * 0.18;
  // Albedo tracks the grain so a proud grain reads light and its trough reads
  // dark; the shader scales this by the per-surface detail albedo amount.
  alb = vec3(0.5 + (a - 0.5) * 0.22 + (b - 0.5) * 0.15
           + gritA * 0.16 + gritB * 0.10 - pit * 0.14);
  rough = 0.5 + (b - 0.5) * 0.5;
  metal = 0.0;
  ao = 1.0 - pit * 0.45 - gritB * 0.10;
  h = clamp(h, 0.0, 1.0);
}


void surface_sample(vec2 uv, float kind, out vec3 albedo, out float height, out vec3 packed) {
    float rough,metal,ao;
    if(kind<0.5) plaster_surface(uv,albedo,height,rough,metal,ao);
    else if(kind<1.5) asphalt_surface(uv,albedo,height,rough,metal,ao);
    else if(kind<2.5) wood_surface(uv,albedo,height,rough,metal,ao);
    else if(kind<3.5) metal_brushed_surface(uv,albedo,height,rough,metal,ao);
    else if(kind<4.5) fabric_surface(uv,albedo,height,rough,metal,ao);
    else if(kind<5.5) concrete_surface(uv,0.0,albedo,height,rough,metal,ao);
    else if(kind<6.5) concrete_surface(uv,1.0,albedo,height,rough,metal,ao);
    else if(kind<7.5) brick_surface(uv,albedo,height,rough,metal,ao);
    else if(kind<8.5) tile_surface(uv,albedo,height,rough,metal,ao);
    else if(kind<9.5) dirt_surface(uv,albedo,height,rough,metal,ao);
    else if(kind<10.5) gravel_surface(uv,albedo,height,rough,metal,ao);
    else if(kind<11.5) metal_painted_surface(uv,albedo,height,rough,metal,ao);
    else if(kind<12.5) metal_rust_surface(uv,albedo,height,rough,metal,ao);
    else if(kind<13.5) rubber_surface(uv,albedo,height,rough,metal,ao);
    else if(kind<14.5) glass_surface(uv,albedo,height,rough,metal,ao);
    else detail_surface(uv,albedo,height,rough,metal,ao);
    packed=clamp(vec3(rough,metal,ao),0.0,1.0);
}
