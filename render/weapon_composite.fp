varying highp vec2 var_uv;
uniform highp sampler2D source_texture;
uniform highp sampler2D flash_texture;
#include "/render/radiance.glsl"
void main() {
    vec4 opaque=texture2D(source_texture,var_uv),flash=texture2D(flash_texture,var_uv);
    vec3 light=decode_radiance(opaque.rgb)*(1.0-flash.a)+flash.rgb*(colour_pipeline.x>.5?1.0:8.0);
    gl_FragColor=vec4(encode_radiance(light),opaque.a*(1.0-flash.a)+flash.a);
}
