varying highp vec3 var_local;
uniform highp sampler2D weapon_depth_texture;
uniform highp vec4 flash_screen;
#include "/render/radiance.glsl"
void main() {
    // Sample the isolated weapon depth, never the world depth buffer.
    if(gl_FragCoord.z>texture2D(weapon_depth_texture,gl_FragCoord.xy*flash_screen.xy).r+.000001) discard;
    vec2 uv=var_local.xy*2.0;
    float r=length(uv);
    float alpha=max(pow(max(0.0,1.0-r),2.0),
        (1.0-smoothstep(.025,.12,abs(uv.x*uv.y)))*(1.0-smoothstep(.15,.96,r))*.65);
    if(alpha<.002) discard;
    vec3 light=mix(vec3(16,7,1),vec3(32,26,14),pow(max(0.0,1.0-r*2.0),2.0));
    gl_FragColor=vec4(clamp(light/(colour_pipeline.x>.5?1.0:8.0),0.0,colour_pipeline.x>.5?65504.0:1.0)*alpha,alpha);
}
