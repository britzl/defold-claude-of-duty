// RG: logarithmic view depth (16 bits); BA: octahedral view normal.
// RG=(1,0) is the clear/sky sentinel. Nearest sampling is mandatory.
const float DEPTH_LOG_RANGE=8.968666793; // log2(1 + world far plane 500 m)
vec2 pack_view_depth(float depth) {
    float d=min(log2(1.0+max(depth,0.0))/DEPTH_LOG_RANGE,.9999);
    vec2 rg=fract(d*vec2(1.0,255.0));
    return vec2(rg.x-rg.y/255.0,rg.y);
}
float unpack_view_depth(vec2 rg) { return exp2(dot(rg,vec2(1.0,1.0/255.0))*DEPTH_LOG_RANGE)-1.0; }
bool depth_covered(vec4 data) { return data.r<.999; }
vec2 oct_sign(vec2 v) { return vec2(v.x>=0.0?1.0:-1.0,v.y>=0.0?1.0:-1.0); }
vec2 pack_view_normal(vec3 n) {
    n/=abs(n.x)+abs(n.y)+abs(n.z);
    return (n.z>=0.0?n.xy:(1.0-abs(n.yx))*oct_sign(n.xy))*.5+.5;
}
vec3 unpack_view_normal(vec2 e) {
    vec2 f=e*2.0-1.0;
    vec3 n=vec3(f,1.0-abs(f.x)-abs(f.y));
    if(n.z<0.0) n.xy=(1.0-abs(n.yx))*oct_sign(n.xy);
    return normalize(n);
}
// Perspective projection scales/offsets from the current world camera.
vec3 view_position(vec2 uv,float depth,vec4 projection) {
    return vec3((uv*2.0-1.0+projection.zw)/projection.xy,-1.0)*depth;
}
