varying highp vec3 var_local;
varying highp vec3 var_surface_normal;
varying highp vec3 var_world;
varying mediump vec3 var_normal;
varying mediump vec4 var_color;
#define WORLD_SCREEN_OCCLUSION
#include "/render/lighting.glsl"
#include "/render/combat_surface.glsl"
#include "/render/depth_normal.glsl"
void main() {
    vec3 albedo,n;float rough,metal;
    combat_surface(var_local,var_surface_normal,var_world,normalize(var_normal),var_color,albedo,rough,metal,n);
    vec3 radiance=lighting(albedo,rough,metal,1.0,var_world,n,normalize(var_normal));
    gl_FragData[0]=vec4(encode_radiance(radiance),1.0);
    gl_FragData[1]=vec4(pack_view_normal(n),rough,1);
    gl_FragData[2]=vec4(reflection_weight,0);
}
