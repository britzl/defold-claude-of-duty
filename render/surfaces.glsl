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


void concrete_surface(vec2 uv, out vec3 alb, out float h, out float rough, out float metal, out float ao){
  const vec2 P = vec2(8.0);
  vec2 p = uv * P + 11.0 * 13.7;

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
  float formAmt = 1.0;
  float jointAmt = 0.0;

  // ---- formwork: horizontal board lines + tie-rod holes ----
  float boards = uv.y * 4.0;
  float bi = floor(boards);
  float bf = fract(boards);
  float seam = (1.0 - surface_ramp(0.0, 0.030, bf)) + (1.0 - surface_ramp(0.0, 0.030, 1.0 - bf));
  seam = clamp(seam, 0.0, 1.0);
  // Boards are never perfectly aligned: each course steps a fraction of a mm.
  float boardStep = (owHash11(mod(bi,4.0) + 11.0) - 0.5) * 0.028 * formAmt;
  h += boardStep;
  h -= seam * 0.055 * formAmt;
  ao -= seam * 0.40 * formAmt;
  c *= 1.0 - seam * 0.16 * formAmt;
  // cement bled along the seam and set lighter
  float bleed = (1.0 - surface_ramp(0.0, 0.10, abs(bf - 0.02))) * 0.5 * formAmt;
  c = mix(c, cLight * 1.05, bleed * 0.35 * owFbm01(p * 8.0, P * 8.0, 3, 0.5));

  // tie holes, plugged, one every other board
  vec2 tf = fract(vec2(uv.x * 3.0, boards * 0.5)) - 0.5;
  float tieRnd = owHash12(mod(floor(vec2(uv.x * 3.0, boards * 0.5)),vec2(3.0,2.0)) + 11.0);
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
float periodic_noise(vec2 uv, vec2 cells)
{
    vec2 p=uv*cells, i=floor(p), f=fract(p);
    f=f*f*(3.0-2.0*f);
    return mix(mix(surface_hash(mod(i,cells)),surface_hash(mod(i+vec2(1,0),cells)),f.x),
        mix(surface_hash(mod(i+vec2(0,1),cells)),surface_hash(mod(i+vec2(1,1),cells)),f.x),f.y);
}
void legacy_surface(vec2 uv, float kind, out vec3 albedo, out float height, out vec3 packed)
{
    float macro=periodic_noise(uv,vec2(4.0));
    float fine=periodic_noise(uv,vec2(48.0));
    float mid=periodic_noise(uv,vec2(16.0));
    float variation=0.78+0.22*macro+0.05*fine;
    float roughness=0.82+0.12*fine, metal=0.0, ao=1.0;
    height=0.45+0.16*mid+0.045*fine;
    if (kind>0.5 && kind<1.5) {
        float aggregate=surface_ramp(0.45,0.73,fine);
        height=0.4+aggregate*0.18+mid*0.045;
        variation=0.72+macro*0.20+aggregate*0.08;
        roughness=0.74+0.20*mid;
        ao=0.88+0.12*aggregate;
    } else if (kind>1.5 && kind<2.5) {
        float grain=periodic_noise(uv,vec2(48.0,4.0));
        float rings=sin(uv.x*75.398+periodic_noise(uv,vec2(4.0))*3.0)*0.5+0.5;
        height=0.42+grain*0.12+rings*0.035;
        variation=0.64+grain*0.25+rings*0.10;
        roughness=0.64+0.22*grain;
        ao=0.88+0.12*grain;
    } else if (kind>2.5 && kind<3.5) {
        float scratch=periodic_noise(uv,vec2(4.0,64.0));
        float rust=surface_ramp(0.63,0.84,macro);
        height=0.5+scratch*0.012+rust*0.10;
        variation=0.82+scratch*0.14-rust*0.20;
        roughness=mix(0.28+0.16*scratch,0.88,rust);
        metal=1.0-rust;
    } else if (kind>3.5) {
        float weave=sin(uv.x*201.062)*sin(uv.y*201.062)*0.5+0.5;
        height=0.5+weave*0.04;
        variation=0.84+macro*0.12+weave*0.04;
        roughness=0.94;
    }
    albedo=vec3(variation);
    packed=vec3(roughness,metal,ao);
}


void surface_sample(vec2 uv, float kind, out vec3 albedo, out float height, out vec3 packed) {
    float rough,metal,ao;
    if(kind<0.5) plaster_surface(uv,albedo,height,rough,metal,ao);
    else if(kind<1.5) asphalt_surface(uv,albedo,height,rough,metal,ao);
    else if(kind<2.5) wood_surface(uv,albedo,height,rough,metal,ao);
    else if(kind>4.5) concrete_surface(uv,albedo,height,rough,metal,ao);
    else { legacy_surface(uv,kind,albedo,height,packed); return; }
    packed=vec3(rough,metal,ao);
}
