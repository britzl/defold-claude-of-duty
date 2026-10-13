varying highp vec2 var_uv;
uniform highp vec4 bake;
#include "/render/radiance.glsl"
#include "/render/sky.glsl"
void main() {
    vec2 p = var_uv * 2.0 - 1.0;
    vec3 d;
    // Cubemap +X,-X,+Y,-Y,+Z,-Z face convention.
    if (bake.x < 0.5) d = vec3(1.0, -p.y, -p.x);
    else if (bake.x < 1.5) d = vec3(-1.0, -p.y, p.x);
    else if (bake.x < 2.5) d = vec3(p.x, 1.0, p.y);
    else if (bake.x < 3.5) d = vec3(p.x, -1.0, -p.y);
    else if (bake.x < 4.5) d = vec3(p.x, -p.y, 1.0);
    else d = vec3(-p.x, -p.y, -1.0);
    gl_FragColor = vec4(encode_radiance(sky_radiance(d)), 1.0);
}
