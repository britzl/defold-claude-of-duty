varying highp vec3 var_local;
varying highp vec3 var_surface_normal;
varying highp vec3 var_world;
varying mediump vec3 var_normal;
varying mediump vec4 var_color;
uniform lowp vec4 tint;
#define VIEWMODEL_SURFACE
#include "/render/lighting.glsl"
#include "/render/combat_surface.glsl"
void main() {
    vec3 albedo,n;float rough,metal;
    combat_surface(var_local,var_surface_normal,var_world,normalize(var_normal),var_color,albedo,rough,metal,n);
    albedo*=linear_colour(tint.rgb);
    vec3 radiance=lighting(albedo,rough,metal,1.0,var_world,n,normalize(var_normal));
    // Reticle is the only emissive opaque part; dark gun metal never self-lights.
    radiance=mix(radiance,albedo*5.0,tint.w);
    gl_FragColor=vec4(encode_radiance(radiance),1.0);
}
