varying highp vec2 var_uv;
uniform highp sampler2D source_texture;
uniform highp sampler2D lower_texture;
uniform highp sampler2D weapon_texture;
uniform highp sampler2D exposure_texture;
uniform highp vec4 bloom_step; // source pixel xy, mode: 0 prefilter,1 down,2 up, manual exposure
#include "/render/radiance.glsl"
#include "/render/photographic.glsl"
vec3 fetch_light(vec2 uv) {
    vec3 c=decode_radiance(texture2D(source_texture,uv).rgb);
    if(bloom_step.z<.5) {
        vec4 weapon=texture2D(weapon_texture,uv);
        c=(c*(1.0-weapon.a)+decode_radiance(weapon.rgb))*bloom_step.w*photo_exposure(texture2D(exposure_texture,vec2(.5)));
        float peak=max(c.r,max(c.g,c.b));
        float soft=clamp(peak-1.6+.9,0.0,1.8);
        float contribution=max(peak-1.6,soft*soft/3.6);
        c*=contribution/max(peak,.0001);
    }
    return c;
}
void main() {
    vec3 sum=vec3(0);float total=0.0;
    // Tent reduction and reconstruction; first-level Karis weights tame fireflies.
    for(int y=-1;y<=1;y++) for(int x=-1;x<=1;x++) {
        float weight=(x==0?2.0:1.0)*(y==0?2.0:1.0);
        vec2 uv=var_uv+vec2(float(x),float(y))*bloom_step.xy;
        vec3 c=fetch_light(uv);
        if(bloom_step.z<.5) weight/=1.0+photo_luma(c);
        sum+=c*weight;total+=weight;
    }
    vec3 colour=sum/total;
    if(bloom_step.z>1.5) colour=mix(colour,decode_radiance(texture2D(lower_texture,var_uv).rgb),.5);
    gl_FragColor=vec4(encode_radiance(colour),1);
}
