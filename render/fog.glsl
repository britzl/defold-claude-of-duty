#include "/render/radiance.glsl"
#include "/render/depth_normal.glsl"
#include "/render/daylight.glsl"
#include "/render/atmosphere.glsl"
uniform highp sampler2D depth_normal_texture;
uniform highp sampler2D sky_texture;
uniform highp mat4 fog_inverse_view;
uniform highp vec4 screen_projection;
uniform highp vec4 fog_data; // scattering, inverse scale height, max distance, extinction
uniform highp vec4 fog_tint;
uniform highp vec4 fog_screen; // full size, half size
uniform highp vec4 fog_options; // march enabled, shadow enabled, deterministic sample phase, diagnostic
void fog_ray(vec2 uv,out vec3 dir,out float distance_to_end,out float depth) {
    vec3 ray=view_position(uv,1.0,screen_projection);
    float ray_length=length(ray);
    dir=mat3(fog_inverse_view)*ray/ray_length;
    vec4 data=texture2D(depth_normal_texture,uv);
    depth=depth_covered(data)?unpack_view_depth(data.rg):500.0;
    distance_to_end=min(depth*ray_length,fog_data.z);
}
float fog_integral(vec3 eye,vec3 dir,float distance_to_end) {
    // Bounded exponent and continuous horizontal-ray limit.
    float d0=exp(clamp(-eye.y*fog_data.y,-40.0,8.0));
    float x=dir.y*fog_data.y*distance_to_end;
    return d0*distance_to_end*(abs(x)<.0001?1.0:(1.0-exp(clamp(-x,-40.0,40.0)))/x);
}
vec3 fog_transmittance(vec3 eye,vec3 dir,float distance_to_end) {
    return exp(-fog_tint.rgb*fog_data.w*fog_integral(eye,dir,distance_to_end));
}
vec3 fog_ambient(vec3 dir) {
    float c=dot(dir,atmo_key.xyz),f=.5+.5*c;
    vec3 cool=decode_radiance(texture2D(sky_texture,vec2(.5,.90)).rgb);
    vec2 warm_uv=vec2(atan(atmo_key.x,atmo_key.z)/6.28318530718+.5,.54);
    vec3 warm=decode_radiance(texture2D(sky_texture,warm_uv).rgb);
    return mix(cool,warm,f*f)*.55;
}
float fog_phase(vec3 dir) {
    float c=dot(dir,atmo_key.xyz);
    float p=mix(at_hg(c,.65),at_hg(c,-.25),.15);
    return p+max(0.0,p-1.0/(4.0*AT_PI))*1.6;
}
