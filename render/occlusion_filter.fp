varying highp vec2 var_uv;
uniform highp sampler2D depth_normal_texture;
uniform lowp sampler2D occlusion_texture;
uniform highp vec4 screen_projection;
uniform highp vec4 screen_size;
#include "/render/depth_normal.glsl"
void main() {
    vec4 centre=texture2D(depth_normal_texture,var_uv);
    if(!depth_covered(centre)) { gl_FragColor=vec4(1.0);return; }
    vec3 n=unpack_view_normal(centre.ba);
    float depth=unpack_view_depth(centre.rg);
    vec3 p=view_position(var_uv,depth,screen_projection);
    vec2 base=floor(var_uv*screen_size.zw);
    vec2 total=vec2(0.0);float weights=0.0;
    for(int y=-1;y<=1;y++) for(int x=-1;x<=1;x++) {
        vec2 uv=(base+vec2(float(x),float(y))+.5)/screen_size.zw;
        if(min(uv.x,uv.y)<=0.0 || max(uv.x,uv.y)>=1.0) continue;
        vec2 sampleUV=(floor(uv*screen_size.xy)+.5)/screen_size.xy;
        vec4 sampleData=texture2D(depth_normal_texture,sampleUV);
        if(!depth_covered(sampleData)) continue;
        vec3 q=view_position(sampleUV,unpack_view_depth(sampleData.rg),screen_projection);
        vec3 sn=unpack_view_normal(sampleData.ba);
        vec3 delta=q-p;
        float plane=max(abs(dot(delta,n)),abs(dot(delta,sn)));
        float tolerance=.012+depth*.001;
        float weight=exp(-plane/tolerance)*pow(max(dot(n,sn),0.0),32.0);
        weight*=exp(-dot(uv-var_uv,uv-var_uv)*screen_size.w*screen_size.w*.7);
        total+=texture2D(occlusion_texture,uv).rg*weight;weights+=weight;
    }
    // No compatible half-res sample at a thin edge: leave it lit, never copy
    // foreground occlusion across a silhouette. Full-resolution output is nearest.
    gl_FragColor=vec4(weights>.01?total/weights:vec2(1.0),0.0,1.0);
}
