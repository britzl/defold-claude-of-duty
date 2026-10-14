// All lighting is linear sRGB. Only the compatibility path encodes radiance.
// RGBA16F keeps interpolation and blending in linear light; alpha is coverage.
uniform highp vec4 colour_pipeline; // x: 1 = linear RGBA16F, 0 = encoded RGBA8
vec3 encode_radiance(vec3 value) {
    if (colour_pipeline.x>0.5) return clamp(value,0.0,65504.0);
    float dither=fract(52.9829189*fract(dot(gl_FragCoord.xy,vec2(0.06711056,0.00583715))));
    return clamp(sqrt(clamp(value/8.0,0.0,1.0))+(dither-0.5)/255.0,0.0,1.0);
}
vec3 decode_radiance(vec3 value) {
    if (colour_pipeline.x>0.5) return value;
    return value * value * 8.0;
}
vec3 linear_colour(vec3 value) {
    vec3 c=max(value,vec3(0.0));
    return mix(pow((c+0.055)/1.055,vec3(2.4)),c/12.92,step(c,vec3(0.04045)));
}
vec3 display_colour(vec3 value) {
    vec3 c=max(value,vec3(0.0));
    return mix(1.055*pow(c,vec3(1.0/2.4))-0.055,c*12.92,step(c,vec3(0.0031308)));
}
