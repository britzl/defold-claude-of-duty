varying highp vec2 var_uv;
uniform highp sampler2D source_texture;
uniform highp sampler2D depth_normal_texture;
uniform highp sampler2D motion_texture;
uniform highp vec4 lens; // mode 0 motion / 1 dof, strength, taps, max radius px
uniform highp vec4 lens_screen; // inverse width/height, current jitter UV
uniform highp vec4 lens_motion; // previous jitter UV, shutter dt normalization, valid
uniform highp mat4 sky_reprojection;
#include "/render/radiance.glsl"
#include "/render/depth_normal.glsl"
#include "/render/motion.glsl"
float depth_at(vec2 uv) {return unpack_view_depth(texture2D(depth_normal_texture,uv+lens_screen.zw).rg);}
float coc(float z,float focus) {
    float near=clamp((focus*.38-z)/max(focus*.38,.1),0.0,1.0)*.55;
    float far=clamp((z-focus*1.15)/18.0,0.0,1.0);
    return (far-near)*3.3*lens.y;
}
void main() {
    float z=depth_at(var_uv);
    vec3 centre=decode_radiance(texture2D(source_texture,var_uv).rgb);
    vec3 sum=centre;float total=1.0;
    vec2 velocity=vec2(0);float radius=0.0;
    float focus=clamp(depth_at(vec2(.5)),3.0,18.0);
    if(lens.x<.5) {
        vec2 uv=var_uv+lens_screen.zw;
        velocity=unpack_motion(texture2D(motion_texture,uv))+lens_screen.zw-lens_motion.xy;
        if(!depth_covered(texture2D(depth_normal_texture,uv))) {
            vec4 old=sky_reprojection*vec4(uv*2.0-1.0,1,1);
            velocity=old.xy/max(old.w,.0001)*.5+.5-lens_motion.xy-var_uv;
        }
        velocity*=lens.y*lens_motion.z*lens_motion.w;
        float pixels=length(velocity/lens_screen.xy);
        velocity*=min(1.0,lens.w/max(pixels,.0001));
        if(pixels<.5) {gl_FragColor=vec4(encode_radiance(centre),1);return;}
    } else {
        radius=coc(z,focus);
        if(abs(radius)<.25) {gl_FragColor=vec4(encode_radiance(centre),1);return;}
    }
    for(int i=0;i<12;i++) {
        if(float(i)>=lens.z-1.0) break;
        float t=(float(i)+.5)/(lens.z-1.0);
        vec2 offset;
        if(lens.x<.5) offset=velocity*(t-.5);
        else {
            float angle=float(i)*2.39996323;
            offset=vec2(cos(angle),sin(angle))*sqrt(t)*abs(radius)*lens_screen.xy;
        }
        vec2 uv=var_uv+offset;
        float sample_z=depth_at(uv);
        // Reject cross-silhouette samples, including foreground leakage into sky.
        float tolerance=max(.08,z*.025);
        float weight=1.0-smoothstep(tolerance,tolerance*2.0,abs(sample_z-z));
        if(lens.x>.5) weight*=step(.15,abs(coc(sample_z,focus)));
        if(min(uv.x,uv.y)<=0.0 || max(uv.x,uv.y)>=1.0) weight=0.0;
        sum+=decode_radiance(texture2D(source_texture,uv).rgb)*weight;total+=weight;
    }
    gl_FragColor=vec4(encode_radiance(sum/total),1);
}
