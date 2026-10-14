varying highp vec2 var_uv;
#include "/render/fog.glsl"
uniform highp sampler2D source_texture;
uniform highp sampler2D fog_texture;
vec3 reconstruct(float depth) {
    vec2 p=var_uv*fog_screen.zw-.5,base=floor(p),fraction=fract(p);
    vec3 sum=vec3(0);float total=0.0;
    for(int y=0;y<2;y++) for(int x=0;x<2;x++) {
        vec2 uv=(base+vec2(float(x),float(y))+.5)/fog_screen.zw;
        vec4 sample_depth=texture2D(depth_normal_texture,uv);
        float other=depth_covered(sample_depth)?unpack_view_depth(sample_depth.rg):500.0;
        float weight=(x==0?1.0-fraction.x:fraction.x)*(y==0?1.0-fraction.y:fraction.y);
        // Reject silhouettes, including geometry against the sky. No epsilon
        // floor that would leak a bright shaft into an unrelated foreground.
        weight*=exp(-abs(other-depth)/max(.08,depth*.015));
        sum+=decode_radiance(texture2D(fog_texture,uv).rgb)*weight;total+=weight;
    }
    return total>.0001?sum/total:vec3(0);
}
void main() {
    vec3 dir;float distance_to_end,depth;
    fog_ray(var_uv,dir,distance_to_end,depth);
    vec3 eye=fog_inverse_view[3].xyz;
    vec3 trans=fog_transmittance(eye,dir,distance_to_end);
    vec3 scatter;
    if(fog_options.x>.5) scatter=reconstruct(depth);
    else {
        float near_od=fog_integral(eye,dir,min(distance_to_end,4.0));
        float od=max(0.0,fog_integral(eye,dir,distance_to_end)-near_od*.5);
        scatter=(sun_radiance.rgb*fog_phase(dir)*.55+fog_ambient(dir))
            *fog_data.x/fog_data.w*(1.0-exp(-fog_data.w*od));
    }
    vec3 colour=decode_radiance(texture2D(source_texture,var_uv).rgb)*trans+scatter;
    if(fog_options.w>1.5) colour=trans;
    else if(fog_options.w>.5) colour=scatter;
    gl_FragColor=vec4(encode_radiance(colour),1);
}
