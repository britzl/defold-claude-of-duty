#include "/render/radiance.glsl"
#include "/render/sky.glsl"
uniform lowp sampler2D shadow_texture;
uniform highp samplerCube environment_texture;
uniform highp mat4 sun_matrix;
uniform highp vec4 eye_position;
uniform highp vec4 features; // shadow, normals, local lights, fog
uniform highp vec4 shadow_params; // texel size, depth bias, environment ready, reserved
uniform highp vec4 light_positions[4]; // xyz, radius
uniform highp vec4 light_colours[4]; // linear RGB radiance
uniform highp vec4 light_minimums[4];
uniform highp vec4 light_maximums[4];
const float PI=3.14159265;
float shadow_visibility(vec3 p, vec3 n)
{
    if (features.x<0.5) return 1.0;
    vec4 clip=sun_matrix*vec4(p+n*0.025,1.0);
    vec3 coord=clip.xyz/clip.w*0.5+0.5;
    if (coord.x<0.002 || coord.x>0.998 || coord.y<0.002 || coord.y>0.998 || coord.z<0.0 || coord.z>1.0) return 1.0;
    float visibility=0.0;
    for (int y=-1;y<=1;y++) for (int x=-1;x<=1;x++) {
        vec2 stored=texture2D(shadow_texture,coord.xy+vec2(float(x),float(y))*shadow_params.x).rg;
        float depth=stored.x+stored.y/255.0;
        visibility+=step(coord.z-shadow_params.y,depth);
    }
    return visibility/9.0;
}
vec3 brdf(vec3 albedo,float roughness,float metal,vec3 n,vec3 v,vec3 l)
{
    vec3 h=normalize(v+l);
    float nl=max(dot(n,l),0.0),nv=max(dot(n,v),0.001),nh=max(dot(n,h),0.0);
    float a=roughness*roughness, a2=a*a;
    float d=a2/(PI*pow(nh*nh*(a2-1.0)+1.0,2.0));
    float k=pow(roughness+1.0,2.0)/8.0;
    float g=(nv/(nv*(1.0-k)+k))*(nl/(nl*(1.0-k)+k));
    vec3 f0=mix(vec3(0.04),albedo,metal);
    vec3 f=f0+(1.0-f0)*pow(1.0-max(dot(h,v),0.0),5.0);
    return ((1.0-f)*(1.0-metal)*albedo/PI + d*g*f/max(4.0*nv*nl,0.001))*nl;
}
vec3 lighting(vec3 albedo,float roughness,float metal,float ao,vec3 p,vec3 n)
{
    vec3 v=normalize(eye_position.xyz-p);
    vec3 sun=normalize(vec3(-0.6,0.85,0.4));
    vec3 result=brdf(albedo,roughness,metal,n,v,sun)*vec3(3.6,3.1,2.45)*shadow_visibility(p,n);
    vec3 hemi=mix(vec3(0.14,0.12,0.085),vec3(0.39,0.48,0.61),n.y*0.5+0.5);
    vec3 reflected=sky_radiance(reflect(-v,n));
    if (shadow_params.z>0.5) reflected=decode_radiance(textureCube(environment_texture,reflect(-v,n)).rgb);
    // Approximate broad rough reflections; no prefiltered mip chain yet.
    reflected=mix(reflected,hemi,roughness*roughness);
    vec3 f0=mix(vec3(0.04),albedo,metal);
    result+=(albedo*(1.0-metal)*hemi+reflected*f0*(1.0-roughness*0.6))*ao;
    if (features.z>0.5) for (int i=0;i<4;i++) {
        vec3 delta=light_positions[i].xyz-p;
        float distance_squared=dot(delta,delta);
        float radius=light_positions[i].w;
        // Include the interior surface itself despite interpolation roundoff;
        // the 1 cm tolerance remains well inside the 30 cm exterior walls.
        vec3 lo=light_minimums[i].xyz-vec3(0.01),hi=light_maximums[i].xyz+vec3(0.01);
        float inside=step(lo.x,p.x)*step(lo.y,p.y)*step(lo.z,p.z)
            *step(p.x,hi.x)*step(p.y,hi.y)*step(p.z,hi.z);
        if (radius>0.0 && distance_squared<radius*radius && inside>0.5) {
            float falloff=pow(1.0-distance_squared/(radius*radius),2.0)/(1.0+distance_squared);
            result+=brdf(albedo,roughness,metal,n,v,delta/max(sqrt(distance_squared),0.001))*light_colours[i].rgb*falloff;
        }
    }
    return result;
}
vec3 height_fog(vec3 radiance,vec3 p)
{
    vec3 ray=p-eye_position.xyz;
    float distance_to_eye=length(ray);
    // Three-point integration is stable for horizontal rays and either direction.
    float density=(exp(-max(eye_position.y,0.0)*0.16)+4.0*exp(-max((p.y+eye_position.y)*0.5,0.0)*0.16)
        +exp(-max(p.y,0.0)*0.16))/6.0;
    float fog=(1.0-exp(-distance_to_eye*0.008*density))*features.w;
    return mix(radiance,sky_radiance(normalize(ray)),fog);
}
