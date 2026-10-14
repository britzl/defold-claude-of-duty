varying highp vec2 var_uv;
uniform highp sampler2D source_texture;
uniform highp vec4 bloom_step; // uv step xy, extraction flag z
#include "/render/radiance.glsl"
vec3 sample_light(vec2 uv) {
    vec3 c=decode_radiance(texture2D(source_texture,uv).rgb);
    if (bloom_step.z>0.5) {
        float peak=max(c.r,max(c.g,c.b));
        c*=max(peak-1.1,0.0)/max(peak,0.001);
    }
    return c;
}
void main() {
    vec3 c=sample_light(var_uv)*0.227027;
    c+=(sample_light(var_uv+bloom_step.xy*1.384615)+sample_light(var_uv-bloom_step.xy*1.384615))*0.316216;
    c+=(sample_light(var_uv+bloom_step.xy*3.230769)+sample_light(var_uv-bloom_step.xy*3.230769))*0.070270;
    gl_FragColor=vec4(encode_radiance(c),1.0);
}
