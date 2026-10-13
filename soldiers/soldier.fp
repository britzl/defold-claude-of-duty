varying highp vec3 var_local;
varying highp vec3 var_world;
varying mediump vec3 var_normal;
varying lowp vec4 var_color;
#include "/render/lighting.glsl"
void main() {
    vec3 p=var_local;
    float blotch=sin(p.x*39.0+sin(p.y*32.0))*sin(p.z*31.0+p.y*28.0);
    float camo=mix(0.70,1.10,smoothstep(-0.15,0.28,blotch));
    vec3 albedo=linear_colour(var_color.rgb*mix(1.0,camo,var_color.a));
    vec3 radiance=lighting(albedo,0.85,0.0,1.0,var_world,normalize(var_normal));
    gl_FragColor=vec4(encode_radiance(height_fog(radiance,var_world)),1.0);
}
