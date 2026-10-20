varying highp vec2 var_uv;
uniform highp sampler2D source_texture;
uniform lowp sampler2D haze_texture;
uniform lowp sampler2D depth_normal_texture;
uniform highp vec4 glass_screen;
#include "/render/depth_normal.glsl"
void main() {
    vec4 field=texture2D(haze_texture,var_uv);
    vec2 offset=clamp((field.rg-field.ba)*.06,vec2(-.018),vec2(.018));
    vec2 uv=clamp(var_uv+offset,glass_screen.xy,vec2(1)-glass_screen.xy);
    vec4 here=texture2D(depth_normal_texture,var_uv+glass_screen.zw);
    vec4 there=texture2D(depth_normal_texture,uv+glass_screen.zw);
    // Do not drag a foreground silhouette across an unrelated background.
    if(depth_covered(here)!=depth_covered(there) || abs(unpack_view_depth(here.rg)-unpack_view_depth(there.rg))>max(.3,unpack_view_depth(here.rg)*.03)) uv=var_uv;
    gl_FragColor=texture2D(source_texture,uv);
}
