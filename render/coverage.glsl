// Vertex alpha: 1 = opaque, 0..1 = perforated sheet, -1 = foliage mask.
// Colour, camera depth/motion, cascade and local shadow passes share this rule.
// No time or per-pass random seed enters coverage.
// Reuse world material bindings: Defold 1.14 permits 32 bindings per set.
// Adding a second atlas sampler plus two uniform blocks exceeds that budget.
#ifdef WORLD_FOLIAGE
#define coverage_texture albedo_texture
#define coverage_info vec4(surface_info.x,surface_info.y,surface_info.w,.45)
#define coverage_rect(i) surface_rects[209+i]
#else
uniform lowp sampler2D coverage_texture;
uniform highp vec4 coverage_rects[11];
uniform highp vec4 coverage_info; // metres, resolution, last mip, alpha cutoff
#define coverage_rect(i) coverage_rects[i]
#endif
vec2 foliage_uv(vec3 p,vec3 n) {
    vec3 a=abs(n);
    // Canonical orientation on BOTH sides of a leaf card.
    return (a.y>.5?vec2(p.x,-p.z):a.x>.5?vec2(p.z,-p.y):p.xy)/coverage_info.x;
}
float foliage_mask(vec2 uv) {
    float footprint=max(length(dFdx(uv)),length(dFdy(uv)));
    float lod=clamp(log2(max(1.0,footprint*coverage_info.y)),0.0,coverage_info.z);
    float lo=floor(lod),hi=min(lo+1.0,coverage_info.z);
    vec4 a=coverage_rect(int(lo)),b=coverage_rect(int(hi));
    return mix(texture2D(coverage_texture,a.xy+fract(uv)*a.zw).a,
        texture2D(coverage_texture,b.xy+fract(uv)*b.zw).a,fract(lod));
}
void surface_clip(vec3 p,vec3 n,float coverage) {
    if(coverage<-.5) {
        vec2 uv=foliage_uv(p,n);
        float alpha=foliage_mask(uv);
        // At subpixel leaf sizes a fixed 4x4 ordered mask retains filtered
        // coverage instead of vanishing at a 0.45 cutoff. Colour/depth share
        // pixels; TAA filters the distant pattern. Shadows use their footprint.
        vec2 q=mod(floor(gl_FragCoord.xy),4.0);
        vec2 a=mod(q,2.0),b=floor(q/2.0);
        float low=2.0*a.x+3.0*a.y-4.0*a.x*a.y;
        float high=2.0*b.x+3.0*b.y-4.0*b.x*b.y;
        float threshold=(4.0*low+high+.5)/16.0;
        float unresolved=smoothstep(.015,.09,max(length(dFdx(uv)),length(dFdy(uv))));
        if(alpha<mix(coverage_info.w,threshold,unresolved)) discard;
        return;
    }
    if(coverage>=.999) return;
    if(coverage<=0.0) discard;
    vec3 a=abs(n);
    vec2 uv=a.y>.5?p.xz:a.x>.5?p.zy:p.xy;
    vec2 cell=fract(uv/.3)-.5;
    if(length(cell)<.48*sqrt(1.0-coverage)) discard;
}
