varying highp vec3 var_position;
varying mediump vec3 var_normal;
varying highp float var_depth;
varying mediump vec3 var_view_normal;
varying lowp float var_coverage;
#include "/render/coverage.glsl"
#include "/render/depth_normal.glsl"
void main() {
    surface_clip(var_position,var_normal,var_coverage);
    gl_FragColor=vec4(pack_view_depth(var_depth),pack_view_normal(normalize(var_view_normal)));
}
