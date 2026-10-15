varying highp vec3 var_world;
varying mediump vec3 var_normal;
varying lowp vec4 var_color;
varying highp vec4 var_edges;
varying mediump vec4 var_masks;
uniform highp vec4 surface;
uniform lowp sampler2D albedo_texture;
uniform lowp sampler2D normal_texture;
uniform lowp sampler2D material_texture;
#define WORLD_SCREEN_OCCLUSION
#include "/render/lighting.glsl"
#include "/render/surface_sampling.glsl"
#include "/render/weathering.glsl"
#define WORLD_FOLIAGE
#include "/render/coverage.glsl"
#include "/render/depth_normal.glsl"
void main() {
    surface_clip(var_world,var_normal,var_color.a);
    vec3 geometric=normalize(var_normal),tangent;
    tangent=abs(geometric.x)>.5?vec3(0,0,1):vec3(1,0,0);
    vec3 bitangent=normalize(cross(geometric,tangent));
    tangent=normalize(cross(bitangent,geometric));
    vec2 world_uv=vec2(dot(var_world,tangent),dot(var_world,bitangent));
    vec2 uv=var_color.a<-.5?foliage_uv(var_world,geometric):world_uv/surface_info.x;
    // Low-frequency continuous warping breaks a repeated tile grid only on
    // unstructured materials. It is anchored in metres, not texture indices.
    if(surface.x<1.5 || (surface.x>4.5 && surface.x<5.5) || (surface.x>8.5 && surface.x<10.5))
        uv+=(vec2(weather_noise(world_uv*.24),weather_noise(world_uv*.21+31.0))-.5)*.28*weather_features.x;
    vec2 dx=dFdx(uv),dy=dFdy(uv);
    vec2 offset=(length(dx)>length(dy)?dx:dy)*.25;
    float lod=surface_lod(dx,dy,surface_info.y);
    vec3 to_eye=eye_position.xyz-var_world;
    float distance_to_eye=length(to_eye);to_eye/=max(distance_to_eye,.001);
    vec3 eye=vec3(dot(to_eye,tangent),dot(to_eye,bitangent),dot(to_eye,geometric));
    float edge=min(min(var_edges.x,var_edges.y),min(var_edges.z,var_edges.w));
    uv=surface_parallax(uv,lod,eye,distance_to_eye,smoothstep(.015,.08,edge));
    vec4 base=surface_pair(albedo_texture,uv,offset,lod);
    vec3 albedo=linear_colour(var_color.rgb)*base.rgb;
    vec3 packed=surface_pair(material_texture,uv,offset,lod).rgb;
    vec3 bump=surface_pair(normal_texture,uv,offset,lod).rgb*2.0-1.0;
    packed.r=sqrt(min(1.0,packed.r*packed.r+max(0.0,1.0-dot(bump,bump))));
    // Shared millimetre-scale maps carry matching albedo/height/normal detail.
    // Fade in screen footprint AND distance, so fine detail cannot shimmer.
    vec2 detail_uv=world_uv/.25;
    float detail_lod=surface_lod(dFdx(detail_uv),dFdy(detail_uv),weather_features.w);
    float detail_fade=(1.0-smoothstep(2.0,5.0,detail_lod))*(1.0-smoothstep(4.0,14.0,distance_to_eye));
    detail_fade*=surface_effects.y*weather_features.y;
    if(detail_fade>.001 && surface.y<.5) {
        float last=log2(weather_features.w);
        vec3 micro=surface_texel(normal_texture,detail_uv,detail_lod,15.0,last).rgb*2.0-1.0;
        float grain=surface_texel(albedo_texture,detail_uv,detail_lod,15.0,last).r-.5;
        albedo*=1.0+grain*.45*detail_fade;
        // Combine slopes (whiteout), retaining the primary surface normal.
        bump=normalize(vec3(bump.xy+micro.xy*detail_fade,bump.z*mix(1.0,micro.z,detail_fade)));
        packed.r=clamp(packed.r-grain*.15*detail_fade,.04,1.0);
    }
    surface_weather(var_world,geometric,base.a,albedo,packed,bump);
    if(surface.y>.5) {
        albedo=linear_colour(var_color.rgb);packed=vec3(surface.z,surface.w,1);
        bump=vec3(0,0,1);
    }
    vec3 n=normalize(geometric*bump.z+(tangent*bump.x+bitangent*bump.y)*features.y);
    vec3 radiance=lighting(albedo,max(packed.r,.04),packed.g,packed.b,var_world,n,geometric);
    gl_FragData[0]=vec4(encode_radiance(radiance),1.0);
    gl_FragData[1]=vec4(pack_view_normal(n),max(packed.r,.04),1);
    gl_FragData[2]=vec4(reflection_weight,0);
}
