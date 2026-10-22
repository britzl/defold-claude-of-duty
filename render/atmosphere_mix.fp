varying highp vec2 var_uv;
uniform highp sampler2D source_texture;
uniform highp sampler2D next_texture;
uniform highp vec4 atmosphere_mix; // fraction, raw-copy flag, environment flag, BRDF row start
#include "/render/radiance.glsl"
void main() {
    vec4 a=texture2D(source_texture,var_uv);
    if(atmosphere_mix.y>.5) { gl_FragColor=a;return; }
    // The invariant BRDF row is linear data. Keep its exact bytes even while
    // the sky-dependent rows blend; a second lookup is unnecessary here.
    if(atmosphere_mix.z>.5 && var_uv.y>=atmosphere_mix.w) {
        gl_FragColor=a;return;
    }
    vec4 b=texture2D(next_texture,var_uv);
    gl_FragColor=vec4(encode_radiance(mix(decode_radiance(a.rgb),decode_radiance(b.rgb),atmosphere_mix.x)),
        mix(a.a,b.a,atmosphere_mix.x));
}
