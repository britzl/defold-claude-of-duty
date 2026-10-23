#include "/render/radiance.glsl"
#include "/render/daylight.glsl"
#include "/render/cloud_density.glsl"
#include "/render/environment_sampling.glsl"
#include "/render/ggx.glsl"
uniform highp vec4 eye_position;
uniform highp vec4 light_colours[4]; // linear RGB radiance, diffuse room-bounce weight
uniform highp vec4 light_minimums[4];
uniform highp vec4 light_maximums[4];
uniform highp vec4 indirect;
uniform highp vec4 lighting_features; // interior gate, filtered reflections, volume count, material mip floor
// Per volume: minimum, maximum, sky floor/feather/door flag, doorway, aperture/diffuse floor.
uniform highp vec4 volume_data[40];
vec2 interior_illumination(vec3 p) {
    vec2 visibility=vec2(1.0);
    if(lighting_features.x<.5) return visibility;
    for(int i=0;i<8;i++) {
        if(float(i)>=lighting_features.z) break;
        vec3 depth=min(p-volume_data[i*5+0].xyz,volume_data[i*5+1].xyz-p);
        float inside=smoothstep(volume_data[i*5+2].y,volume_data[i*5+2].z,min(depth.x,min(depth.y,depth.z)));
        if(inside<=0.0) continue;
        float sky=volume_data[i*5+2].x;
        vec2 fill=vec2(sky,max(sky,volume_data[i*5+4].w));
        if(volume_data[i*5+2].w>.5) {
            vec4 door=volume_data[i*5+3],size=volume_data[i*5+4];
            float inward=max(0.0,(door.x-p.x)*door.w);
            float side=max(0.0,abs(p.z-door.y)-size.x*.5);
            float height=max(0.0,max(door.z-p.y,p.y-door.z-size.y));
            // Smooth, bounded doorway fill; closed upper windows admit no sky.
            float opening=exp(-(inward*inward+4.0*side*side+4.0*height*height)/(size.z*size.z));
            opening*=1.0-smoothstep(door.z+size.y,door.z+size.y+.35,p.y);
            fill=mix(fill,vec2(.85),opening);
        }
        visibility=min(visibility,mix(vec2(1.0),fill,inside));
    }
    return visibility;
}
float interior_visibility(vec3 p) { return interior_illumination(p).x; }
#include "/render/shadows.glsl"
#include "/render/local_shadows.glsl"
uniform highp vec4 flash_positions[2];
uniform highp vec4 flash_colours[2];
vec3 reflection_weight;
vec3 brdf(vec3 albedo,float roughness,float metal,vec3 n,vec3 v,vec3 l)
{
    vec3 h=normalize(v+l);
    float nl=max(dot(n,l),0.0),nv=max(dot(n,v),0.001),nh=max(dot(n,h),0.0);
    float a=roughness*roughness, a2=a*a;
    float d=a2/(PI*pow(nh*nh*(a2-1.0)+1.0,2.0));
    float g=ggx_g1(nv,a2)*ggx_g1(nl,a2);
    vec3 f0=mix(vec3(0.04),albedo,metal);
    vec3 f=f0+(1.0-f0)*pow(1.0-max(dot(h,v),0.0),5.0);
    return ((1.0-f)*(1.0-metal)*albedo/PI + d*g*f/max(4.0*nv*nl,0.001))*nl;
}
#ifdef WORLD_SCREEN_OCCLUSION
uniform lowp sampler2D occlusion_texture;
uniform highp vec4 screen_effects; // inverse dimensions, AO/contact enable
#endif
vec3 lighting(vec3 albedo,float roughness,float metal,float ao,vec3 p,vec3 n,vec3 geometric)
{
    reflection_weight=vec3(0);
    // Gate on the final shading normal; the geometric normal only sets bias.
    vec3 sun=normalize(sun_direction.xyz);
    bool sunlit=dot(n,sun)>0.0;
    float visibility=1.0;
    // Diagnostics show shadow coverage even where direct lighting is zero.
    if(sunlit || shadow_data[17].w>.5) visibility=shadow_visibility(p,geometric);
    if(shadow_data[17].w>.5) return shadow_debug(p,visibility);
    vec2 screen_visibility=vec2(1.0);
#ifdef WORLD_SCREEN_OCCLUSION
    screen_visibility=mix(vec2(1.0),texture2D(occlusion_texture,gl_FragCoord.xy*screen_effects.xy).rg,screen_effects.zw);
#endif
    vec3 v=normalize(eye_position.xyz-p);
    vec3 result=vec3(0);
    // The direct BRDF is zero on unlit faces, but indirect light still applies.
    if(sunlit) {
        visibility=min(visibility,screen_visibility.y)*cloud_shadow(p.xz,sun_direction.xyz);
        result=brdf(albedo,roughness,metal,n,v,sun)*sun_radiance.rgb*visibility;
    }
    vec2 indoor=interior_illumination(p);
    float nv=max(dot(n,v),.0001);
    vec3 reflected=environment_specular(reflect(-v,n),lighting_features.y>.5?roughness:0.0);
    vec3 f0=mix(vec3(0.04),albedo,metal);
    vec2 integrated=environment_brdf(nv,roughness);
    vec3 specular_weight=clamp(f0*integrated.x+integrated.y,0.0,1.0);
    vec3 diffuse=environment_row(n,environment_layout.z+1.0)*indirect.x;
    // Restrained warm bounce from sunlit surfaces on the opposite side; diffuse
    // only, gated indoors along with the sky. Material cavities are applied once.
    diffuse+=sun_radiance.rgb*ground_radiance.rgb*indirect.w*max(dot(n,-sun)*.5+.5,0.0);
    // Macro AO and authored material cavities overlap: take their minimum,
    // not their product. Glossy reflections retain directional environment light.
    float diffuse_ao=min(ao,screen_visibility.x);
    float specular_ao=min(ao,mix(1.0,screen_visibility.x,roughness*roughness));
    // Room diffuse fill approximates scattered light; reflections retain the
    // stricter sky-visibility gate. Both still follow the environment at night.
    reflection_weight=specular_weight*indirect.y*specular_ao*indoor.x;
    result+=(1.0-specular_weight)*(1.0-metal)*albedo*diffuse*diffuse_ao*indoor.y
        +reflected*specular_weight*indirect.y*specular_ao*indoor.x;
    if (features.z>0.5) for (int i=0;i<4;i++) {
        vec3 delta=light_positions[i].xyz-p;
        float distance_squared=dot(delta,delta);
        float radius=light_positions[i].w;
        // Include the interior surface itself despite interpolation roundoff;
        // the 1 cm tolerance remains well inside the 30 cm exterior walls.
        vec3 lo=light_minimums[i].xyz-vec3(0.01),hi=light_maximums[i].xyz+vec3(0.01);
        float inside=step(lo.x,p.x)*step(lo.y,p.y)*step(lo.z,p.z)
            *step(p.x,hi.x)*step(p.y,hi.y)*step(p.z,hi.z);
        if (radius>0.0 && inside>0.5) {
            // Coarse reflected lamp light fills only its authored room bounds.
            // It follows source colour/intensity/fade, remains diffuse and uses
            // contact AO; direct shadows still shape the stronger nearby light.
            result+=(1.0-specular_weight)*(1.0-metal)*albedo*diffuse_ao
                *light_colours[i].rgb*light_colours[i].w;
            if(distance_squared>=radius*radius) continue;
            vec3 l=delta/max(sqrt(distance_squared),0.001);
            if(dot(n,l)<=0.0) continue;
            float falloff=pow(1.0-distance_squared/(radius*radius),2.0)/(1.0+distance_squared);
            result+=brdf(albedo,roughness,metal,n,v,l)*light_colours[i].rgb*falloff*local_visibility(i,p,geometric);
        }
    }
    if(features.z>.5) for(int i=0;i<2;i++) {
        vec3 delta=flash_positions[i].xyz-p;float d2=dot(delta,delta),radius=flash_positions[i].w;
        if(radius>0.0 && d2<radius*radius) {
            vec3 l=normalize(delta);
            if(dot(n,l)<=0.0) continue;
            float falloff=pow(1.0-d2/(radius*radius),2.0)/(1.0+d2);
            result+=brdf(albedo,roughness,metal,n,v,l)*flash_colours[i].rgb*falloff;
        }
    }
    return result;
}
