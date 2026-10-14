varying highp vec2 var_uv;
uniform highp vec4 probe;
#include "/render/radiance.glsl"
void main() {
    if (probe.x>1.5) {
        gl_FragColor=vec4(encode_radiance(vec3(16.0)),0.25);
    } else if (probe.x>0.5) {
        if (var_uv.x<0.875) discard;
        gl_FragColor=vec4(encode_radiance(vec3(16.0)),0.25);
    } else {
        float value=var_uv.x<0.125?0.0:var_uv.x<0.25?0.001:var_uv.x<0.375?0.018:
            var_uv.x<0.5?0.18:var_uv.x<0.625?1.0:var_uv.x<0.75?8.0:var_uv.x<0.875?16.0:32.0;
        gl_FragColor=vec4(encode_radiance(vec3(value)),1.0);
    }
}
