varying highp vec2 var_uv;
uniform highp vec4 bake_region; // normalized y offset, height
uniform highp sampler2D brdf_texture;
#include "/render/radiance.glsl"
#include "/render/sky.glsl"
#include "/render/environment_sampling.glsl"
#include "/render/ggx.glsl"
#include "/render/environment_samples.glsl"
void main() {
    vec2 pixel=vec2(var_uv.x,bake_region.x+var_uv.y*bake_region.y)*environment_layout.y*vec2(6,environment_layout.w);
    vec2 tile=floor(pixel/environment_layout.y);
    vec2 uv=(pixel-tile*environment_layout.y-1.0)/environment_layout.x;
    float row=tile.y;
    if(row>environment_layout.w-1.5) {
        // Initial bake broadcasts the one cached LUT tile across this row.
        // Runtime updates preserve the row and only filter sky-dependent rows.
        vec2 lut_pixel=vec2(pixel.x-tile.x*environment_layout.y,pixel.y);
        gl_FragColor=texture2D(brdf_texture,lut_pixel/(environment_layout.y*vec2(6,environment_layout.w)));return;
    }
    vec3 n=environment_face(tile.x,uv*2.0-1.0);
    if(row<.5) { gl_FragColor=vec4(encode_radiance(sky_radiance(n)),1);return; }
    bool diffuse=row>environment_layout.z+.5;
    float rough=(row-1.0)/(environment_layout.z-1.0);
    if(!diffuse && rough<.001) { gl_FragColor=vec4(encode_radiance(sky_environment(n)),1);return; }
    vec3 up=abs(n.y)<.999?vec3(0,1,0):vec3(1,0,0);
    vec3 tangent=normalize(cross(up,n)),bitangent=cross(n,tangent);
    vec3 result=vec3(0);float total=0.0;
    for(int i=0;i<128;i++) {
        vec2 xi=sample_point(i);vec3 l;
        if(diffuse) {
            float phi=2.0*PI*xi.x,s=sqrt(xi.y);
            l=vec3(cos(phi)*s,sin(phi)*s,sqrt(1.0-xi.y));
        } else l=reflect(vec3(0,0,-1),ggx_half(xi,rough));
        float weight=diffuse?1.0:max(l.z,0.0);
        result+=sky_environment(tangent*l.x+bitangent*l.y+n*l.z)*weight;total+=weight;
    }
    // Cosine sampled irradiance / PI; the Lambert factor is already included.
    gl_FragColor=vec4(encode_radiance(result/max(total,.0001)),1);
}
