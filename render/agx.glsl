// Neutral AgX port from the local Three.js src/render/glsl.js and Kaigen
// shaders/claude_of_duty/cod_final.glsl references. Input/output: linear sRGB.
// Copyright (c) 2026 mshumer, MIT; see THIRD_PARTY_NOTICES.md.
// Log-space look is identity (slope/power/saturation = 1); no display grade.
vec3 agx_contrast(vec3 x) {
    vec3 x2=x*x, x4=x2*x2;
    return 15.5*x4*x2-40.14*x4*x+31.96*x4-6.868*x2*x+0.4298*x2+0.1191*x-0.00232;
}
vec3 agx_neutral(vec3 colour) {
    const mat3 to_rec2020=mat3(vec3(0.6274,0.0691,0.0164),vec3(0.3293,0.9195,0.0880),vec3(0.0433,0.0113,0.8956));
    const mat3 to_srgb=mat3(vec3(1.6605,-0.1246,-0.0182),vec3(-0.5876,1.1329,-0.1006),vec3(-0.0728,-0.0083,1.1187));
    const mat3 inset=mat3(vec3(0.856627153315983,0.137318972929847,0.11189821299995),
        vec3(0.0951212405381588,0.761241990602591,0.0767994186031903),
        vec3(0.0482516061458583,0.101439036467562,0.811302368396859));
    const mat3 outset=mat3(vec3(1.1271005818144368,-0.1413297634984383,-0.14132976349843826),
        vec3(-0.11060664309660323,1.157823702216272,-0.11060664309660294),
        vec3(-0.016493938717834573,-0.016493938717834257,1.2519364065950405));
    colour=inset*(to_rec2020*colour);
    colour=clamp((log2(max(colour,vec3(1e-10)))+12.47393)/(4.026069+12.47393),0.0,1.0);
    colour=outset*agx_contrast(colour);
    // AgX's internal EOTF is part of the curve, not the display conversion.
    colour=pow(max(colour,vec3(0.0)),vec3(2.2));
    return clamp(to_srgb*colour,0.0,1.0);
}
