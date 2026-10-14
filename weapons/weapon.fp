varying highp vec3 var_world;
varying mediump vec3 var_normal;
varying lowp vec4 var_color;
uniform lowp vec4 tint;
#include "/render/lighting.glsl"
void main() {
    vec3 albedo=linear_colour(var_color.rgb*tint.rgb);
    float metal=var_color.a;
    vec3 radiance=lighting(albedo,mix(0.80,0.35,metal),metal,1.0,var_world,normalize(var_normal),normalize(var_normal));
    radiance=mix(radiance,albedo*5.0,tint.w);
#ifdef WORLD_EFFECT
    gl_FragData[0]=vec4(encode_radiance(radiance),1.0);
    gl_FragData[1]=vec4(0);gl_FragData[2]=vec4(0);
#else
    gl_FragColor=vec4(encode_radiance(radiance),1.0);
#endif
}
