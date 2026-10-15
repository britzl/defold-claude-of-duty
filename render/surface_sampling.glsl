// Explicit mip rectangles avoid atlas bleed on all backends, including GLES.
// 20 recipes x 11 slots (short chains repeat their last level).
uniform highp vec4 surface_rects[220];
uniform highp vec4 surface_info; // metres, resolution, relief metres, last mip
uniform highp vec4 surface_effects; // parallax metres, micro amount, weather amount
uniform highp vec4 weather_features; // weather, micro, parallax, detail resolution
vec4 surface_texel(sampler2D map,vec2 uv,float lod,float kind,float last) {
    lod=clamp(lod,0.0,last);
    float lo=floor(lod),hi=min(lo+1.0,last);
    vec4 a=surface_rects[int(kind)*11+int(lo)];
    vec4 b=surface_rects[int(kind)*11+int(hi)];
    return mix(texture2D(map,a.xy+fract(uv)*a.zw),texture2D(map,b.xy+fract(uv)*b.zw),fract(lod));
}
vec4 surface_pair(sampler2D map,vec2 uv,vec2 offset,float lod) {
    return 0.5*(surface_texel(map,uv-offset,lod,surface.x,surface_info.w)+
        surface_texel(map,uv+offset,lod,surface.x,surface_info.w));
}
// Derivatives are taken before wrapping and before the parallax branch.
float surface_lod(vec2 dx,vec2 dy,float resolution) {
    float lx=length(dx),ly=length(dy);
    return max(0.0,log2(max(max(min(lx,ly),max(lx,ly)*0.5)*resolution,1.0)));
}
vec2 surface_parallax(vec2 uv,float lod,vec3 eye,float distance_to_eye,float edge_fade) {
    float fade=(1.0-smoothstep(2.0,6.0,distance_to_eye))*smoothstep(0.18,0.45,eye.z)*edge_fade;
    float amount=surface_effects.x*weather_features.z*features.y*fade/surface_info.x;
    if(amount<0.00001 || lod>3.0) return uv;
    vec2 delta=-eye.xy/max(eye.z,0.35)*amount/12.0;
    vec2 q=uv;float layer=1.0;
    float h=surface_texel(albedo_texture,q,lod,surface.x,surface_info.w).a;
    float previous=layer-h;
    for(int i=0;i<12;i++) {
        if(layer<=h) break;
        previous=layer-h;q+=delta;layer-=1.0/12.0;
        h=surface_texel(albedo_texture,q,lod,surface.x,surface_info.w).a;
    }
    float over=h-layer;
    return q-delta*clamp(over/max(previous+over,0.00001),0.0,1.0);
}
