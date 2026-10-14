varying highp vec3 var_world;
varying mediump vec3 var_normal;
varying lowp vec4 var_color;
uniform highp vec4 surface;
uniform lowp sampler2D albedo_texture;
uniform lowp sampler2D normal_texture;
uniform lowp sampler2D material_texture;
#include "/render/lighting.glsl"
void main() {
    vec3 n=normalize(var_normal), tangent, bitangent;
    // Right-handed basis on every side, including down-facing soffits.
    if (abs(n.y)>0.5) tangent=vec3(1.0,0.0,0.0);
    else if (abs(n.x)>0.5) tangent=vec3(0.0,0.0,1.0);
    else tangent=vec3(1.0,0.0,0.0);
    bitangent=normalize(cross(n,tangent));
    tangent=normalize(cross(bitangent,n));
    vec2 tile=fract(vec2(dot(var_world,tangent),dot(var_world,bitangent))*0.5);
    vec2 uv=(tile*254.0+1.0)/256.0;
    uv.x=(uv.x+surface.x)/5.0;
    vec3 albedo=linear_colour(var_color.rgb)*texture2D(albedo_texture,uv).rgb;
    vec3 packed=texture2D(material_texture,uv).rgb;
    vec3 bump=texture2D(normal_texture,uv).rgb*2.0-1.0;
    // Uniform-material laboratory spheres exercise the production lighting path.
    if (surface.y>0.5) {
        albedo=linear_colour(var_color.rgb);
        packed=vec3(surface.z,surface.w,1.0);
        bump=vec3(0.0,0.0,1.0);
    }
    n=normalize(n*bump.z+(tangent*bump.x+bitangent*bump.y)*features.y);
    vec3 radiance=lighting(albedo,max(packed.r,surface.y>0.5?0.04:0.18),packed.g,packed.b,var_world,n);
    gl_FragColor=vec4(encode_radiance(height_fog(radiance,var_world)),1.0);
}
