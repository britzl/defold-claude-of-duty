varying highp vec3 var_position;
varying mediump vec3 var_normal;
varying highp float var_depth;
varying mediump vec3 var_view_normal;
varying lowp float var_coverage;
#include "/render/coverage.glsl"
#include "/render/depth_normal.glsl"
#include "/render/motion.glsl"
varying highp vec4 var_current_clip;
varying highp vec4 var_previous_clip;
varying highp float var_previous_depth;
varying mediump vec3 var_previous_normal;
void main() {
    surface_clip(var_position,var_normal,var_coverage);
    gl_FragData[0]=vec4(pack_view_depth(var_depth),pack_view_normal(normalize(var_view_normal)));
    vec2 motion=(var_previous_clip.xy/max(var_previous_clip.w,.0001)-var_current_clip.xy/var_current_clip.w)*.5;
    gl_FragData[1]=pack_motion(motion);
    gl_FragData[2]=var_previous_depth>0.0 && max(abs(motion.x),abs(motion.y))<.99
        ?vec4(pack_view_depth(var_previous_depth),pack_view_normal(normalize(var_previous_normal)))
        :vec4(1.0,0.0,.5,.5);
}
