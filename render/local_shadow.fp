varying highp vec3 var_cutout_position;
varying mediump vec3 var_cutout_normal;
varying lowp float var_coverage;
uniform highp vec4 local_shadow_position;
#include "/render/coverage.glsl"
void main() {
    surface_clip(var_cutout_position,var_cutout_normal,var_coverage);
    float d=min(length(var_cutout_position-local_shadow_position.xyz)/local_shadow_position.w,.99999);
    vec2 packed=fract(d*vec2(1,255));packed.x-=packed.y/255.0;
    gl_FragColor=vec4(packed,0,1);
}
