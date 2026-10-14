varying highp vec3 var_world;
varying mediump vec3 var_normal;
varying lowp vec4 var_color;
uniform highp vec4 surface;
uniform lowp sampler2D albedo_texture;
uniform lowp sampler2D normal_texture;
uniform lowp sampler2D material_texture;
#include "/render/lighting.glsl"
uniform highp vec4 surface_rects[66];
vec4 surface_texel(sampler2D map,vec2 uv,float lod) {
    float lo=floor(lod),hi=min(lo+1.0,surface.x>2.5 && surface.x<4.5?8.0:10.0);
    vec4 a=surface_rects[int(surface.x)*11+int(lo)];
    vec4 b=surface_rects[int(surface.x)*11+int(hi)];
    vec2 tile=fract(uv);
    return mix(texture2D(map,a.xy+tile*a.zw),texture2D(map,b.xy+tile*b.zw),fract(lod));
}
void main() {
    vec3 n=normalize(var_normal), tangent, bitangent;
    // Right-handed basis on every face, including downward-facing soffits.
    if (abs(n.y)>0.5) tangent=vec3(1.0,0.0,0.0);
    else if (abs(n.x)>0.5) tangent=vec3(0.0,0.0,1.0);
    else tangent=vec3(1.0,0.0,0.0);
    bitangent=normalize(cross(n,tangent));
    tangent=normalize(cross(bitangent,n));
    float metres=surface.x<0.5?2.2:surface.x<1.5?3.0:surface.x>4.5?2.5:2.0;
    float resolution=surface.x>2.5 && surface.x<4.5?256.0:1024.0;
    vec2 uv=vec2(dot(var_world,tangent),dot(var_world,bitangent))/metres;
    // Derivatives before wrapping. Two taps along the major footprint axis
    // preserve detail at grazing angles; trilinear levels bound minification.
    vec2 dx=dFdx(uv),dy=dFdy(uv);
    float lx=length(dx),ly=length(dy);
    vec2 major=lx>ly?dx:dy;
    float footprint=max(min(lx,ly),max(lx,ly)*0.5)*resolution;
    float lod=clamp(log2(max(footprint,1.0)),0.0,log2(resolution));
    vec2 offset=major*0.25;
    vec3 albedo=linear_colour(var_color.rgb)*0.5*(surface_texel(albedo_texture,uv-offset,lod).rgb+surface_texel(albedo_texture,uv+offset,lod).rgb);
    vec3 packed=0.5*(surface_texel(material_texture,uv-offset,lod).rgb+surface_texel(material_texture,uv+offset,lod).rgb);
    vec3 bump=(surface_texel(normal_texture,uv-offset,lod).rgb+surface_texel(normal_texture,uv+offset,lod).rgb)-1.0;
    // Lost normal variance broadens the highlight instead of sparkling.
    packed.r=sqrt(min(1.0,packed.r*packed.r+max(0.0,1.0-dot(bump,bump))));
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
