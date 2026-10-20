varying highp vec2 var_uv;
uniform highp vec4 bake_region; // normalized y offset, height
#include "/render/radiance.glsl"
#include "/render/sky.glsl"
#include "/render/environment_sampling.glsl"
#include "/render/ggx.glsl"
// Deterministic Hammersley sequence without integer/bitwise GLSL requirements.
vec2 sample_point(int index) {
    float n=float(index),r=0.0,p=.5;
    for(int bit=0;bit<7;bit++) { r+=mod(n,2.0)*p;n=floor(n*.5);p*=.5; }
    return vec2((float(index)+.5)/128.0,r);
}
void main() {
    vec2 pixel=vec2(var_uv.x,bake_region.x+var_uv.y*bake_region.y)*environment_layout.y*vec2(6,environment_layout.w);
    vec2 tile=floor(pixel/environment_layout.y);
    vec2 uv=(pixel-tile*environment_layout.y-1.0)/environment_layout.x;
    float row=tile.y;
    if(row>environment_layout.w-1.5) {
        vec2 q=clamp((pixel-tile*environment_layout.y-1.5)/(environment_layout.x-1.0),0.0,1.0);
        float nv=max(q.x,.0001),rough=q.y,a=max(rough*rough,.0001);
        vec3 v=vec3(sqrt(max(0.0,1.0-nv*nv)),0,nv);vec2 integral=vec2(0);
        for(int i=0;i<128;i++) {
            vec3 h=ggx_half(sample_point(i),rough),l=reflect(-v,h);
            float nl=max(l.z,0.0),vh=max(dot(v,h),0.0);
            if(nl>0.0) {
                float weight=ggx_g1(nv,a*a)*ggx_g1(nl,a*a)*vh/max(h.z*nv,.00001);
                float f=pow(1.0-vh,5.0);integral+=vec2(1.0-f,f)*weight;
            }
        }
        gl_FragColor=vec4(integral/128.0,0,1);return;
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
