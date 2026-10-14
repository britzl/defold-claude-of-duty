varying highp float var_shadow_depth;
varying highp vec3 var_cutout_position;
varying mediump vec3 var_cutout_normal;
varying lowp float var_coverage;
#include "/render/coverage.glsl"
void main() {
    surface_clip(var_cutout_position,var_cutout_normal,var_coverage);
    float d=clamp(var_shadow_depth,0.0,0.99999);
    vec2 packed=fract(d*vec2(1.0,255.0));
    packed.x-=packed.y/255.0;
    gl_FragColor=vec4(packed,0.0,1.0);
}
