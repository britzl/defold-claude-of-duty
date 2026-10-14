varying highp vec2 var_uv;
uniform highp sampler2D source_texture;
uniform highp sampler2D weapon_texture;
uniform highp sampler2D depth_normal_texture;
uniform highp sampler2D previous_texture;
uniform highp vec4 meter; // mode: 0 meter, 1 reduce, 2 adapt, 3 manual; source pixel xy in yz
uniform highp vec4 adaptation; // dt, reset, min multiplier, max multiplier
#include "/render/radiance.glsl"
#include "/render/depth_normal.glsl"
#include "/render/photographic.glsl"
void main() {
    if(meter.x<.5) {
        // Per-tap log clamp prevents a solar disc or flash from pumping exposure.
        vec2 sum=vec2(0);
        for(int y=0;y<2;y++) for(int x=0;x<2;x++) {
            vec2 uv=var_uv+(vec2(float(x),float(y))-.5)/64.0;
            vec3 c=decode_radiance(texture2D(source_texture,uv).rgb);
            vec4 weapon=texture2D(weapon_texture,uv);
            c=c*(1.0-weapon.a)+decode_radiance(weapon.rgb);
            float lum=clamp(photo_luma(c),.000244140625,40.0);
            vec2 d=(uv-.5)*2.0;
            float weight=exp(-dot(d,d)*1.1);
            if(!depth_covered(texture2D(depth_normal_texture,uv))) weight*=mix(1.0,.15,smoothstep(.06,.3,lum));
            sum+=vec2((log2(lum)+12.0)/18.0*weight,weight)*.25;
        }
        gl_FragColor=vec4(photo_pack(sum.x),photo_pack(sum.y));
    } else if(meter.x<1.5) {
        vec2 sum=vec2(0);
        for(int y=0;y<4;y++) for(int x=0;x<4;x++) {
            vec4 s=texture2D(source_texture,var_uv+(vec2(float(x),float(y))-1.5)*meter.yz);
            sum+=vec2(photo_unpack(s.rg),photo_unpack(s.ba))/16.0;
        }
        gl_FragColor=vec4(photo_pack(sum.x),photo_pack(sum.y));
    } else if(meter.x<2.5) {
        vec4 s=texture2D(source_texture,vec2(.5));
        float logLum=photo_unpack(s.rg)/max(photo_unpack(s.ba),.0001)*18.0-12.0;
        float target=log2(clamp(.18/exp2(logLum),adaptation.z,adaptation.w));
        float old=log2(photo_exposure(texture2D(previous_texture,vec2(.5))));
        if(adaptation.y>.5) old=target;
        float speed=target>old?1.4:3.2;
        float value=mix(old,target,1.0-exp(-adaptation.x*speed));
        gl_FragColor=vec4(photo_pack((value+2.0)/4.0),photo_pack((target+2.0)/4.0));
    } else gl_FragColor=vec4(photo_pack(.5),photo_pack(.5));
}
