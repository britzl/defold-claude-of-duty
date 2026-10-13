varying highp vec2 var_uv;
uniform highp mat4 inverse_view_proj;
uniform highp vec4 eye_position;
#include "/render/radiance.glsl"
#include "/render/sky.glsl"
void main() {
    vec4 p = inverse_view_proj * vec4(var_uv * 2.0 - 1.0, 1.0, 1.0);
    gl_FragColor = vec4(encode_radiance(sky_radiance(p.xyz / p.w - eye_position.xyz)), 1.0);
}
