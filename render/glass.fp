varying highp vec3 var_world;
varying mediump vec3 var_normal;
varying highp float var_depth;
uniform lowp sampler2D depth_normal_texture;
uniform lowp sampler2D albedo_texture;
uniform lowp sampler2D normal_texture;
uniform lowp sampler2D material_texture;
uniform highp vec4 glass_screen; // inverse dimensions, opaque projection jitter
uniform highp vec4 surface;
#include "/render/lighting.glsl"
#include "/render/surface_sampling.glsl"
#include "/render/depth_normal.glsl"
void main() {
    vec2 screen_uv=gl_FragCoord.xy*glass_screen.xy+glass_screen.zw;
    vec4 depth=texture2D(depth_normal_texture,screen_uv);
    if(depth_covered(depth) && var_depth>unpack_view_depth(depth.rg)+.015) discard;
    vec3 v=normalize(eye_position.xyz-var_world);
    vec3 geometric=normalize(var_normal);
    geometric*=dot(geometric,v)>=0.0?1.0:-1.0;
    vec3 tangent=abs(geometric.x)>.5?vec3(0,0,1):vec3(1,0,0);
    vec3 bitangent=normalize(cross(geometric,tangent));
    vec2 uv=vec2(dot(var_world,tangent),dot(var_world,bitangent))/surface_info.x;
    float lod=surface_lod(dFdx(uv),dFdy(uv),surface_info.y);
    vec3 bump=surface_pair(normal_texture,uv,vec2(0),lod).rgb*2.0-1.0;
    vec3 n=normalize(geometric*bump.z+(tangent*bump.x+bitangent*bump.y)*features.y*.3);
    vec3 packed=surface_pair(material_texture,uv,vec2(0),lod).rgb;
    float roughness=clamp(packed.r,.045,.3);
    float smudge=surface_pair(albedo_texture,uv,vec2(0),lod).r;
    float fresnel=.04+.96*pow(1.0-max(dot(n,v),0.0),5.0);
    float absorption=.035+(1.0-smudge)*.05;
    float alpha=1.0-(1.0-fresnel)*(1.0-absorption);
    // Dielectric Fresnel with no diffuse term. Alpha attenuates the background;
    // very small tinted dust scatter gives dirt coverage without opaque glass.
    vec3 radiance=lighting(vec3(.04),roughness,1.0,1.0,var_world,n,geometric);
    radiance+=environment_row(n,environment_layout.z+1.0)*vec3(.65,.85,.78)*absorption*.15;
    // Transparent layers store premultiplied LINEAR light on both pipelines.
    gl_FragColor=vec4(clamp(radiance/(colour_pipeline.x>.5?1.0:8.0),0.0,colour_pipeline.x>.5?65504.0:1.0),alpha);
}
