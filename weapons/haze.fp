varying highp float var_depth;
varying mediump vec2 var_uv;
uniform highp vec4 particle;
uniform highp vec4 glass_screen;
uniform lowp sampler2D depth_normal_texture;
#include "/render/depth_normal.glsl"
void main() {
    // The offset target is half-sized; glass_screen.xy is its reciprocal size.
    vec4 scene=texture2D(depth_normal_texture,gl_FragCoord.xy*glass_screen.xy+glass_screen.zw);
    float gap=depth_covered(scene)?unpack_view_depth(scene.rg)-var_depth:500.0;
    float r=length(var_uv);
    if(gap<=0.0 || r>=1.0) discard;
    float mask=pow(max(0.0,1.0-r*r),2.0);
    vec2 flow=vec2(sin(var_uv.y*13.0+particle.w*9.0+particle.z*30.0),cos(var_uv.x*11.0-particle.w*8.0+particle.z*21.0));
    if(particle.x<10.0) {mask=1.0-smoothstep(.02,.14,abs(r-.72));flow=var_uv/max(r,.001);}
    vec2 offset=flow*mask*particle.y*smoothstep(0.0,.3,gap)*smoothstep(.1,.5,var_depth)*.25;
    // Separate positive/negative channels permit additive offsets in RGBA8.
    gl_FragColor=vec4(max(offset,vec2(0)),max(-offset,vec2(0)));
}
