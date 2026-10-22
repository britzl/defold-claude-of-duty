varying highp vec2 var_uv;
uniform highp vec4 environment_layout;
#include "/render/ggx.glsl"
#include "/render/environment_samples.glsl"
void main() {
    // One padded tile, independent of the sky, weather and cube direction.
    vec2 pixel=floor(var_uv*environment_layout.y)+.5;
    vec2 q=clamp((pixel-1.5)/(environment_layout.x-1.0),0.0,1.0);
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
    gl_FragColor=vec4(integral/128.0,0,1);
}
