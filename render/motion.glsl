// Signed UV displacement, two 16-bit components in portable RGBA8.
vec2 pack_motion_component(float value) {
    vec2 rg=fract(clamp(value*.5+.5,0.0,.99999)*vec2(1.0,255.0));
    return vec2(rg.x-rg.y/255.0,rg.y);
}
vec4 pack_motion(vec2 value) { return vec4(pack_motion_component(value.x),pack_motion_component(value.y)); }
vec2 unpack_motion(vec4 value) { return vec2(dot(value.rg,vec2(1.0,1.0/255.0)),dot(value.ba,vec2(1.0,1.0/255.0)))*2.0-1.0; }
