varying highp vec2 var_uv;
uniform lowp sampler2D scene_texture;
uniform lowp sampler2D weapon_texture;
uniform lowp sampler2D bloom_texture;
uniform lowp sampler2D debug_texture;
uniform lowp samplerCube environment_texture;
uniform highp vec4 post; // exposure, bloom strength, debug view, reserved
#include "/render/radiance.glsl"
vec3 tone_map(vec3 c) {
    c*=post.x;
    c=clamp((c*(2.51*c+0.03))/(c*(2.43*c+0.59)+0.14),0.0,1.0);
    return pow(c,vec3(1.0/2.2));
}
void main() {
    if (post.z>4.5) {
        float longitude=(var_uv.x*2.0-1.0)*3.14159265;
        float latitude=(var_uv.y-0.5)*3.14159265;
        vec3 d=vec3(cos(latitude)*sin(longitude),sin(latitude),cos(latitude)*cos(longitude));
        gl_FragColor=vec4(tone_map(decode_radiance(textureCube(environment_texture,d).rgb)),1.0);
    } else if (post.z>0.5) {
        vec3 data=texture2D(debug_texture,var_uv).rgb;
        if (post.z>3.5) data=vec3(data.r+data.g/255.0);
        gl_FragColor=vec4(data,1.0);
    } else {
        vec3 world=decode_radiance(texture2D(scene_texture,var_uv).rgb);
        world+=decode_radiance(texture2D(bloom_texture,var_uv).rgb)*post.y;
        vec4 weapon=texture2D(weapon_texture,var_uv);
        // Fog and bloom apply to the world; tone mapping is identical for both.
        vec3 combined=mix(world,decode_radiance(weapon.rgb),weapon.a);
        gl_FragColor=vec4(tone_map(combined),1.0);
    }
}
