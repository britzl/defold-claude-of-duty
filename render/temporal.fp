varying highp vec2 var_uv;
uniform highp sampler2D source_texture;
uniform highp sampler2D history_texture;
uniform highp sampler2D depth_normal_texture;
uniform highp sampler2D previous_depth_texture;
uniform highp sampler2D motion_texture;
uniform highp sampler2D expected_texture;
uniform highp vec4 temporal_params; // inverse width/height, valid history, debug
uniform highp vec4 jitter; // current xy, previous zw in UV units
uniform highp mat4 sky_reprojection;
#include "/render/radiance.glsl"
#include "/render/depth_normal.glsl"
#include "/render/motion.glsl"
float luminance(vec3 c) { return dot(c,vec3(.2126,.7152,.0722)); }
// Work in reversible, luminance-compressed YCoCg so HDR outliers cannot dominate.
vec3 working(vec3 c) {
    c/=1.0+luminance(c);
    return vec3(dot(c,vec3(.25,.5,.25)),(c.r-c.b)*.5,(-c.r+2.0*c.g-c.b)*.25);
}
vec3 radiance(vec3 c) {
    c=vec3(c.x+c.y-c.z,c.x+c.z,c.x-c.y-c.z);
    return max(c,0.0)/max(1.0-luminance(c),.0001);
}
vec3 current(vec2 uv) { return working(decode_radiance(texture2D(source_texture,uv).rgb)); }
bool inside(vec2 uv) { return min(uv.x,uv.y)>0.0 && max(uv.x,uv.y)<1.0; }
float compatible(vec4 old,vec4 expected,bool covered) {
    if(covered!=depth_covered(old)) return 0.0;
    if(!covered) return 1.0;
    float z=unpack_view_depth(expected.rg);
    if(!depth_covered(expected) || abs(unpack_view_depth(old.rg)-z)>max(.025,z*.006)) return 0.0;
    return step(.85,dot(unpack_view_normal(old.ba),unpack_view_normal(expected.ba)));
}
void main() {
    vec2 pixel=temporal_params.xy;
    vec2 uv=var_uv+jitter.xy;
    vec4 depth=texture2D(depth_normal_texture,uv);
    bool covered=depth_covered(depth);
    vec2 motion=unpack_motion(texture2D(motion_texture,uv));
    vec4 expected=texture2D(expected_texture,uv);
    vec2 previous=uv+motion-jitter.zw;
    if(!covered) {
        vec4 sky=sky_reprojection*vec4(uv*2.0-1.0,1.0,1.0);
        previous=sky.xy/max(sky.w,.0001)*.5+.5-jitter.zw;
    }
    vec3 colour=current(uv),lo=colour,hi=colour,mean=vec3(0),square=vec3(0);
    for(int y=-1;y<=1;y++) for(int x=-1;x<=1;x++) {
        vec3 sample_colour=current(uv+vec2(float(x),float(y))*pixel);
        lo=min(lo,sample_colour);hi=max(hi,sample_colour);
        mean+=sample_colour;square+=sample_colour*sample_colour;
    }
    mean/=9.0;
    vec3 sigma=sqrt(max(square/9.0-mean*mean,vec3(0)));
    lo=max(lo,mean-1.25*sigma);hi=min(hi,mean+1.25*sigma);
    vec3 history=vec3(0);float confidence=0.0;
    // Reject individual bilinear taps: a valid centre alone leaks foreground
    // history across silhouettes and newly exposed surfaces.
    vec2 base=floor(previous/pixel-.5),fraction=fract(previous/pixel-.5);
    for(int y=0;y<2;y++) for(int x=0;x<2;x++) {
        vec2 offset=vec2(float(x),float(y));
        vec2 sample_uv=(base+offset+.5)*pixel;
        vec2 weight=mix(1.0-fraction,fraction,offset);
        float valid=temporal_params.z>.5 && inside(sample_uv)?compatible(texture2D(previous_depth_texture,sample_uv+jitter.zw),expected,covered):0.0;
        float w=weight.x*weight.y*valid;
        if(w>0.0) history+=working(decode_radiance(texture2D(history_texture,sample_uv).rgb))*w;
        confidence+=w;
    }
    history/=max(confidence,.00001);
    // Clip along the ray to the variance box, preserving chroma direction.
    vec3 centre=(lo+hi)*.5,extent=max((hi-lo)*.5,vec3(.0001));
    vec3 delta=history-centre;
    float scale=max(1.0,max(abs(delta.x/extent.x),max(abs(delta.y/extent.y),abs(delta.z/extent.z))));
    history=centre+delta/scale;
    float speed=length((previous-var_uv)/pixel);
    float weight=mix(.92,.78,clamp(speed/12.0,0.0,1.0))*confidence*temporal_params.z;
    weight*=1.0-clamp(abs(history.x-colour.x)*3.0,0.0,.85);
    if(!inside(previous)) weight=0.0;
    vec3 result=radiance(mix(colour,history,weight));
    if(temporal_params.w>1.5) result=vec3(weight);
    else if(temporal_params.w>.5) result=vec3(clamp((previous-var_uv)/pixel/8.0+.5,0.0,1.0),covered?1.0:0.0);
    // Diagnostic values are data, not encoded scene radiance.
    gl_FragColor=vec4(temporal_params.w>.5?result:encode_radiance(result),1.0);
}
