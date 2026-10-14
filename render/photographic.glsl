// Portable 16-bit unit packing, used by exposure even on the RGBA8 path.
vec2 photo_pack(float v) {
    vec2 p=fract(clamp(v,0.0,.99999)*vec2(1.0,255.0));
    return vec2(p.x-p.y/255.0,p.y);
}
float photo_unpack(vec2 p) { return dot(p,vec2(1.0,1.0/255.0)); }
float photo_exposure(vec4 p) { return exp2(photo_unpack(p.rg)*4.0-2.0); }
float photo_luma(vec3 c) { return dot(c,vec3(.2126,.7152,.0722)); }
