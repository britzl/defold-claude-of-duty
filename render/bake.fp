varying highp vec2 var_uv;
uniform highp vec4 bake;
#include "/render/surfaces.glsl"
void main() {
    float kind=floor(var_uv.x*5.0);
    // Each tile has one texel of periodic padding on all sides.
    vec2 uv=(vec2(fract(var_uv.x*5.0),var_uv.y)*256.0-1.0)/254.0;
    vec3 albedo, packed; float h;
    surface_sample(uv,kind,albedo,h,packed);
    if (bake.x<0.5) gl_FragColor=vec4(albedo,1.0);
    else if (bake.x<1.5) {
        vec3 unused_a,unused_p; float hx,hy;
        surface_sample(uv+vec2(1.0/254.0,0),kind,unused_a,hx,unused_p);
        surface_sample(uv+vec2(0,1.0/254.0),kind,unused_a,hy,unused_p);
        vec3 normal=normalize(vec3((h-hx)*3.0,(h-hy)*3.0,1.0));
        gl_FragColor=vec4(normal*0.5+0.5,1.0);
    } else gl_FragColor=vec4(packed,1.0);
}
