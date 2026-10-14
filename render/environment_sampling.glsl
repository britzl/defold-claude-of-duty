// Cubemap faces in a padded 2D atlas. Explicit levels work on every existing
// backend without writable cubemap mips. Each gutter evaluates the neighbouring
// direction; filtering never reads a different roughness or an unrelated face.
uniform highp sampler2D environment_texture;
uniform highp vec4 environment_layout; // face size, padded stride, reflection levels, rows
vec3 environment_face(float face,vec2 p) {
    if(face<.5) return normalize(vec3(1,-p.y,-p.x));
    if(face<1.5) return normalize(vec3(-1,-p.y,p.x));
    if(face<2.5) return normalize(vec3(p.x,1,p.y));
    if(face<3.5) return normalize(vec3(p.x,-1,-p.y));
    if(face<4.5) return normalize(vec3(p.x,-p.y,1));
    return normalize(vec3(-p.x,-p.y,-1));
}
vec2 environment_uv(vec3 d,float row) {
    vec3 a=abs(d);vec2 p;float face;
    if(a.x>=a.y && a.x>=a.z) {
        face=d.x>0.0?0.0:1.0;p=vec2(d.x>0.0?-d.z:d.z,-d.y)/a.x;
    } else if(a.y>=a.z) {
        face=d.y>0.0?2.0:3.0;p=vec2(d.x,d.y>0.0?d.z:-d.z)/a.y;
    } else {
        face=d.z>0.0?4.0:5.0;p=vec2(d.z>0.0?d.x:-d.x,-d.y)/a.z;
    }
    return (vec2(face,row)*environment_layout.y+1.0+(p*.5+.5)*environment_layout.x)
        /(environment_layout.y*vec2(6,environment_layout.w));
}
vec3 environment_row(vec3 d,float row) {
    return decode_radiance(texture2D(environment_texture,environment_uv(d,row)).rgb);
}
vec3 environment_specular(vec3 d,float roughness) {
    float level=clamp(roughness,0.0,1.0)*(environment_layout.z-1.0);
    float lo=floor(level),hi=min(lo+1.0,environment_layout.z-1.0);
    return mix(environment_row(d,lo+1.0),environment_row(d,hi+1.0),level-lo);
}
vec2 environment_brdf(float nv,float roughness) {
    vec2 uv=vec2(1.5+clamp(nv,0.0,1.0)*(environment_layout.x-1.0),
        (environment_layout.w-1.0)*environment_layout.y+1.5+clamp(roughness,0.0,1.0)*(environment_layout.x-1.0));
    // LUT is linear data, never radiance encoded or display transformed.
    return texture2D(environment_texture,uv/(environment_layout.y*vec2(6,environment_layout.w))).rg;
}
