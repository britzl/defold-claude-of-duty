varying highp vec2 var_uv;
uniform highp sampler2D scene_texture;
uniform highp sampler2D weapon_texture;
uniform highp sampler2D bloom_texture;
uniform lowp sampler2D debug_texture;
uniform highp samplerCube environment_texture;
uniform highp vec4 atlas_window;
uniform highp vec4 post; // exposure, bloom strength, debug view, atlas half (0=all,1=lower,2=upper)
#include "/render/radiance.glsl"
#include "/render/agx.glsl"
vec3 tone_map(vec3 c) {
    return display_colour(agx_neutral(c*post.x));
}
void main() {
    if (post.z>5.5) {
        // Bottom: radiance / 64. Middle: shared AgX. Top: transfer functions,
        // linear filtering across 0.18/1, hardware blending, layer mix, alpha.
        vec3 source=decode_radiance(texture2D(scene_texture,var_uv).rgb);
        vec3 value;
        if (var_uv.y<1.0/3.0) value=source/64.0;
        else if (var_uv.y<2.0/3.0) value=tone_map(source);
        else if (var_uv.x<0.125) value=display_colour(vec3(0.0031308));
        else if (var_uv.x<0.25) value=linear_colour(vec3(0.04045));
        else if (var_uv.x<0.375) value=display_colour(vec3(0.18));
        else if (var_uv.x<0.5) value=linear_colour(vec3(0.5));
        else if (var_uv.x<0.625) value=decode_radiance(texture2D(scene_texture,vec2(0.5,0.5)).rgb);
        else if (var_uv.x<0.75) value=decode_radiance(texture2D(scene_texture,vec2(0.9375,0.5)).rgb)/64.0;
        else if (var_uv.x<0.875) {
            vec4 weapon=texture2D(weapon_texture,vec2(0.5));
            value=mix(decode_radiance(texture2D(scene_texture,vec2(0.6875,0.5)).rgb),decode_radiance(weapon.rgb),weapon.a)/64.0;
        } else value=vec3(texture2D(weapon_texture,vec2(0.5)).a);
        gl_FragColor=vec4(value,1.0);
    } else if (post.z>4.5) {
        float longitude=(var_uv.x*2.0-1.0)*3.14159265;
        float latitude=(var_uv.y-0.5)*3.14159265;
        vec3 d=vec3(cos(latitude)*sin(longitude),sin(latitude),cos(latitude)*cos(longitude));
        gl_FragColor=vec4(tone_map(decode_radiance(textureCube(environment_texture,d).rgb)),1.0);
    } else if (post.z>0.5) {
        vec2 uv=atlas_window.xy+var_uv*atlas_window.zw;
        if(post.z<3.5 && post.w>0.5) uv.y=uv.y*0.5+(post.w>1.5?0.5:0.0);
        vec3 data=texture2D(debug_texture,uv).rgb;
        if (post.z>3.5) data=vec3(data.r+data.g/255.0);
        gl_FragColor=vec4(data,1.0);
    } else {
        vec3 world=decode_radiance(texture2D(scene_texture,var_uv).rgb);
        world+=decode_radiance(texture2D(bloom_texture,var_uv).rgb)*post.y;
        vec4 weapon=texture2D(weapon_texture,var_uv);
        // Fog and bloom apply to the world; tone mapping is identical for both.
        vec3 combined=mix(world,decode_radiance(weapon.rgb),weapon.a);
        float dither=fract(52.9829189*fract(dot(gl_FragCoord.xy,vec2(0.06711056,0.00583715))));
        gl_FragColor=vec4(clamp(tone_map(combined)+(dither-0.5)/255.0,0.0,1.0),1.0);
    }
}
