varying highp vec2 var_uv;
#include "/render/fog.glsl"
#include "/render/cloud_density.glsl"
#include "/render/shadows.glsl"
// Four bilinear comparisons, no surface bias/PCSS in empty air.
float fog_cascade(int c,vec3 p) {
    vec4 point=vec4(p,1);
    vec3 sc=vec3(dot(shadow_data[c*4],point),dot(shadow_data[c*4+1],point),dot(shadow_data[c*4+2],point))*.5+.5;
    if(any(lessThan(sc,vec3(0))) || any(greaterThan(sc,vec3(1)))) return 1.0;
    float bias=shadow_data[c*4+3].x*shadow_data[c*4+3].y*.45;
    return shadow_compare(c,sc.xy,sc.z-bias);
}
float fog_visibility(vec3 p) {
    if(fog_options.y<.5 || features.x<.5) return 1.0;
    float depth=dot(shadow_data[16],vec4(p,1));
    if(depth>=shadow_data[15].z) return 1.0;
    int c=shadow_index(depth);
    float result=fog_cascade(c,p),blend=smoothstep(shadow_data[c*4+3].w,shadow_data[c*4+3].z,depth);
    if(c<3 && blend>0.0) result=mix(result,fog_cascade(c+1,p),blend);
    if(c==3) result=mix(result,1.0,blend);
    return result;
}
void main() {
    vec3 dir;float distance_to_end,depth;
    fog_ray(var_uv,dir,distance_to_end,depth);
    vec3 eye=fog_inverse_view[3].xyz,light=vec3(0),trans=vec3(1);
    vec3 ambient=fog_ambient(dir);float phase=fog_phase(dir);
    float cloud_near=cloud_shadow(eye.xz,atmo_key.xyz);
    float cloud_far=cloud_shadow((eye+dir*distance_to_end).xz,atmo_key.xyz);
    float jitter=fract(52.9829189*fract(dot(gl_FragCoord.xy,vec2(.06711056,.00583715)))+fog_options.z*.618033989);
    for(int i=0;i<40;i++) {
        float a=float(i)/40.0,b=float(i+1)/40.0;
        float start=a*a*distance_to_end,end=b*b*distance_to_end;
        // Every segment integrates its FULL length; jitter moves only the sample.
        float t=mix(start,end,.15+.70*jitter),dt=end-start;
        vec3 p=eye+dir*t;
        // Low-frequency advected density preserves broad shafts without crawling noise.
        float flow=sin(p.x*.045+weather_data.z*.08)*cos(p.z*.038-weather_data.z*.055);
        float density=exp(clamp(-p.y*fog_data.y,-40.0,8.0))*(1.0+.16*flow);
        float visible=fog_visibility(p)*mix(cloud_near,cloud_far,t/max(distance_to_end,.001));
        vec3 ext=fog_tint.rgb*fog_data.w*density;
        vec3 segment=exp(-ext*dt);
        vec3 source=(sun_radiance.rgb*(visible*phase)+ambient*(.12+.88*visible))
            *fog_data.x*density*smoothstep(0.0,4.0,t);
        light+=trans*source*(1.0-segment)/max(ext,vec3(.000001));trans*=segment;
    }
    gl_FragColor=vec4(encode_radiance(light),1);
}
