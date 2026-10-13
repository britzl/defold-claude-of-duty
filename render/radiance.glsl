// Square-root encoded light in RGBA8, with a fixed 0..8 range. This preserves
// dark tones without requiring float colour-buffer extensions on WebGL 2.
// Alpha remains coverage for the weapon pass. Decode before lighting/compositing.
vec3 encode_radiance(vec3 value) {
    float dither=fract(52.9829189*fract(dot(gl_FragCoord.xy,vec2(0.06711056,0.00583715))));
    return clamp(sqrt(clamp(value/8.0,0.0,1.0))+(dither-0.5)/255.0,0.0,1.0);
}
vec3 decode_radiance(vec3 value) { return value * value * 8.0; }
vec3 linear_colour(vec3 value) { return pow(max(value, vec3(0.0)), vec3(2.2)); }
