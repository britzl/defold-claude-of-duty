varying highp vec2 var_uv;
uniform highp sampler2D source_texture;
uniform highp sampler2D glass_texture;
#include "/render/radiance.glsl"
void main() {
    vec3 base=decode_radiance(texture2D(source_texture,var_uv).rgb);
    vec4 glass=texture2D(glass_texture,var_uv);
    vec3 radiance=glass.rgb*(colour_pipeline.x>.5?1.0:8.0)+base*(1.0-glass.a);
    gl_FragColor=vec4(encode_radiance(radiance),1);
}
