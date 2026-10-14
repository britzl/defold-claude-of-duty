varying highp vec2 var_uv;
uniform highp sampler2D depth_normal_texture;
uniform highp vec4 screen_projection;
uniform highp vec4 screen_size; // full width/height, half width/height
uniform highp vec4 occlusion_params; // radius, ray length, AO enabled, contact enabled
uniform highp vec4 sun_view;
#include "/render/depth_normal.glsl"
const float AO_PI=3.141592654;
vec2 depth_uv(vec2 uv) { return (floor(uv*screen_size.xy)+.5)/screen_size.xy; }
bool on_screen(vec2 uv) { return min(uv.x,uv.y)>0.0 && max(uv.x,uv.y)<1.0; }
float arc(float h,float n,float cosN,float sinN) {
    return .25*(-cos(2.0*h-n)+cosN+2.0*h*sinN);
}
float horizon(vec2 uv,vec3 p,vec3 n,vec3 v,float previous) {
    if(!on_screen(uv)) return previous;
    uv=depth_uv(uv);
    vec4 data=texture2D(depth_normal_texture,uv);
    if(!depth_covered(data)) return previous;
    vec3 delta=view_position(uv,unpack_view_depth(data.rg),screen_projection)-p;
    float len2=dot(delta,delta);
    if(len2<.000001) return previous;
    // Normal bias removes quantization self-occlusion; metre-space falloff
    // prevents unrelated foreground silhouettes darkening distant backgrounds.
    delta-=n*.008;
    float c=dot(normalize(delta),v);
    float fall=clamp(len2/(occlusion_params.x*occlusion_params.x),0.0,1.0);
    return max(previous,mix(c,previous,fall*fall));
}
float ambient_visibility(vec2 uv,vec3 p,vec3 n) {
    vec3 v=normalize(-p);
    float radiusPx=min(96.0,occlusion_params.x*screen_projection.y*.5*screen_size.y/max(.1,-p.z));
    float sum=0.0,unoccluded=0.0;
    // Fixed slices: no frame noise or temporal history before rendering step 8.
    for(int slice=0;slice<4;slice++) {
        float phi=(float(slice)+.125)*AO_PI/4.0;
        vec2 direction=vec2(cos(phi),sin(phi));
        vec3 tangent=vec3(direction,0.0);
        vec3 axis=normalize(cross(tangent,v));
        vec3 projected=n-axis*dot(n,axis);
        float plen=length(projected);
        if(plen<.0001) continue;
        vec3 ortho=normalize(tangent-v*dot(tangent,v));
        float cosN=clamp(dot(projected/plen,v),-1.0,1.0);
        float angle=(dot(ortho,projected)>=0.0?1.0:-1.0)*acos(cosN);
        float sinN=sin(angle),positive=-1.0,negative=-1.0;
        for(int step=0;step<6;step++) {
            float f=(float(step)+.5)/6.0;
            vec2 offset=direction*(1.0+radiusPx*f*f)/screen_size.xy;
            positive=horizon(uv+offset,p,n,v,positive);
            negative=horizon(uv-offset,p,n,v,negative);
        }
        float a=angle+max(-acos(clamp(negative,-1.0,1.0))-angle,-AO_PI*.5);
        float b=angle+min(acos(clamp(positive,-1.0,1.0))-angle,AO_PI*.5);
        sum+=plen*(arc(a,angle,cosN,sinN)+arc(b,angle,cosN,sinN));
        unoccluded+=plen*(arc(angle-AO_PI*.5,angle,cosN,sinN)+arc(angle+AO_PI*.5,angle,cosN,sinN));
    }
    float visibility=clamp(sum/max(unoccluded,.0001),0.0,1.0);
    return mix(max(.15,visibility),1.0,smoothstep(60.0,100.0,-p.z));
}
float contact_visibility(vec3 p,vec3 n) {
    vec3 light=normalize(sun_view.xyz);
    if(dot(n,light)<=.02) return 1.0;
    vec3 origin=p+n*(.008+min(.025,-p.z*.0008));
    float blocked=0.0;
    for(int step=0;step<12;step++) {
        float t=(float(step)+1.0)/12.0;
        vec3 ray=origin+light*occlusion_params.y*t;
        if(ray.z>=-.1) break;
        vec2 uv=(ray.xy/-ray.z*screen_projection.xy-screen_projection.zw)*.5+.5;
        if(!on_screen(uv)) break;
        vec4 data=texture2D(depth_normal_texture,depth_uv(uv));
        if(!depth_covered(data)) continue;
        float depth=unpack_view_depth(data.rg);
        float difference=-ray.z-depth;
        float bias=.006+depth*.0004;
        if(difference>bias && difference<.12) {
            float edge=min(min(uv.x,uv.y),min(1.0-uv.x,1.0-uv.y));
            blocked=(1.0-t*t)*smoothstep(0.0,.025,edge);break;
        }
    }
    return 1.0-blocked*(1.0-smoothstep(40.0,70.0,-p.z));
}
void main() {
    vec2 uv=depth_uv(var_uv);
    vec4 data=texture2D(depth_normal_texture,uv);
    if(!depth_covered(data)) { gl_FragColor=vec4(1.0);return; }
    vec3 p=view_position(uv,unpack_view_depth(data.rg),screen_projection);
    vec3 n=unpack_view_normal(data.ba);
    float ao=occlusion_params.z>.5?ambient_visibility(uv,p,n):1.0;
    float contact=occlusion_params.w>.5?contact_visibility(p,n):1.0;
    gl_FragColor=vec4(ao,contact,0.0,1.0);
}
