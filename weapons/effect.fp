varying highp vec3 var_world;
varying mediump vec3 var_normal;
varying mediump vec4 var_color;
uniform lowp vec4 tint;
#include "/render/lighting.glsl"
void main() {
    vec3 albedo=linear_colour(tint.rgb);
    vec3 radiance=lighting(albedo,.48,tint.a<0.0?.75:0.0,1.0,var_world,normalize(var_normal),normalize(var_normal));
    radiance=mix(radiance,albedo*12.0,max(0.0,tint.a));
    gl_FragData[0]=vec4(encode_radiance(radiance),1.0);
    gl_FragData[1]=vec4(0);gl_FragData[2]=vec4(0);
}
