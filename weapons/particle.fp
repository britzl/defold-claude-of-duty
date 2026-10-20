varying highp vec3 var_world;
varying mediump vec3 var_normal;
varying mediump vec3 var_view_normal;
varying highp float var_depth;
varying mediump vec2 var_uv;
uniform highp vec4 particle; // kind, opacity, seed, normalized age
uniform lowp vec4 tint; // colour, decal variant
uniform highp vec4 glass_screen;
uniform highp vec4 combat_features;
uniform lowp sampler2D depth_normal_texture;
#include "/render/lighting.glsl"
#include "/render/depth_normal.glsl"
#include "/render/transparency.glsl"
float cloud(vec2 p) {
    float a=sin(p.x*9.0+particle.z*25.0+particle.w*1.7)*sin(p.y*11.0+sin(p.x*6.0));
    float b=sin(p.x*23.0+p.y*17.0+particle.z*31.0)*sin(p.y*27.0-p.x*14.0);
    return .65+.23*a+.12*b;
}
void main() {
    vec4 scene=texture2D(depth_normal_texture,gl_FragCoord.xy*glass_screen.xy+glass_screen.zw);
    float gap=depth_covered(scene)?unpack_view_depth(scene.rg)-var_depth:500.0;
    float r=length(var_uv),alpha=0.0,k=particle.x;
    bool decal=(k>1.5 && k<2.5) || (k>13.5 && k<15.5);
    vec3 radiance;
    if(decal) {
        if(combat_features.z<.5 || !depth_covered(scene) || abs(gap)>.025 ||
            dot(normalize(var_view_normal),unpack_view_normal(scene.ba))<.8) discard;
        float angle=atan(var_uv.y,var_uv.x);
        float edge=r*(1.0+.15*sin(angle*9.0+particle.z*18.0));
        float rim=smoothstep(.19,.35,edge)*(1.0-smoothstep(.4,.95,edge));
        alpha=(1.0-smoothstep(.28,.9,edge))*.94;
        if(k>14.5) { // irregular blood spatter, with disconnected small drops
            alpha=(1.0-smoothstep(.15,.8,r))*smoothstep(.38,.62,cloud(var_uv*1.8));
        } else if(k>13.5) {
            alpha=(1.0-smoothstep(.1,.95,r))*(.55+.45*cloud(var_uv));rim=0.0;
        } else if(tint.a>.5 && tint.a<1.5) {
            alpha*=1.0-smoothstep(.1,.45,abs(var_uv.x));
        } else if(tint.a>1.5) {
            alpha*=.65+.35*sin(angle*12.0+particle.z*40.0)*sin(angle*12.0+particle.z*40.0);
        }
        vec3 albedo=linear_colour(tint.rgb)*mix(.16,1.5,rim);
        radiance=lighting(albedo,k>14.5?.36:.92,0.0,1.0,var_world,normalize(var_normal),normalize(var_normal));
    } else {
        if(gap<=0.0) discard;
        float noise=cloud(var_uv);
        vec3 ambient=environment_row(vec3(0,1,0),environment_layout.z+1.0)*interior_visibility(var_world);
        if(k>.5 && k<1.5) {
            alpha=pow(max(0.0,1.0-r),2.0);
            alpha=max(alpha,(1.0-smoothstep(.035,.16,abs(var_uv.x*var_uv.y)))*(1.0-smoothstep(.2,.95,r))*.55);
            radiance=mix(vec3(18,9,2),vec3(32,27,15),pow(max(0.0,1.0-r*2.0),2.0));
        } else if(k>2.5 && k<3.5) { // velocity-aligned cooling spark
            alpha=(1.0-smoothstep(.15,.9,abs(var_uv.y)))*(1.0-smoothstep(.25,1.0,abs(var_uv.x)));
            radiance=mix(vec3(24,15,5),vec3(1.8,.12,.015),particle.w);
        } else if(k>7.5 && k<8.5) {
            float edge=r+(noise-.6)*.35;
            alpha=(1.0-smoothstep(.45,.96,edge))*(.75+.25*noise);
            radiance=mix(vec3(20,11,2.5),vec3(2.8,.22,.012),clamp(edge*.7+particle.w*.6,0.0,1.0));
        } else if(k>8.5 && k<9.5) {
            alpha=(1.0-smoothstep(.025,.13,abs(r-.72)))*(1.0-smoothstep(.9,1.0,r));
            radiance=tint.rgb*1.2;
        } else if(k>9.5 && k<10.5) {
            alpha=pow(max(0.0,1.0-r*r),3.0);radiance=tint.rgb*(ambient+.15);
        } else if(k>3.5 && k<7.5 || k>10.5) {
            float shape=max(abs(var_uv.x)*.8+var_uv.y*.45,-var_uv.y*.9);
            if(k>4.5 && k<5.5 || k>12.5) shape=max(abs(var_uv.x)*3.5,abs(var_uv.y)*.9);
            if(k>6.5 && k<7.5 || k>10.5 && k<11.5) shape=r;
            if(k>11.5 && k<12.5) shape=abs(var_uv.x)*1.7+abs(var_uv.y)*.7;
            alpha=1.0-smoothstep(.65,.92,shape);
            radiance=linear_colour(tint.rgb)*(ambient+sun_radiance.rgb*.3);
            if(k>5.5 && k<6.5) {alpha*=.65;radiance+=vec3(2.5)*pow(max(0.0,sin(particle.w*24.0+particle.z*31.0)),12.0);}
            if(k>6.5 && k<7.5) alpha*=noise;
        } else {
            alpha=pow(max(0.0,1.0-r*r),2.0)*noise;
            float sun=shadow_visibility(var_world,normalize(var_normal));
            radiance=linear_colour(tint.rgb)*(ambient+sun_radiance.rgb*sun*.30);
        }
        if(combat_features.y>.5) alpha*=smoothstep(0.0,(k<.5 || k>7.5 && k<9.5)?.22:.025,gap);
        alpha*=smoothstep(.04,.16,var_depth);
    }
    alpha*=particle.y*(1.0-smoothstep(.92,1.0,max(abs(var_uv.x),abs(var_uv.y))));
    if(alpha<.001) discard;
    if(features.w>.5) {
        vec3 ray=var_world-eye_position.xyz;float distance_to_eye=length(ray);
        float slope=ray.y*.16,base=exp(clamp(-eye_position.y*.16,-40.0,8.0));
        float od=base*distance_to_eye*(abs(slope)<.0001?1.0:(1.0-exp(clamp(-slope,-40.0,40.0)))/slope);
        vec3 trans=exp(-vec3(.88,.96,1.08)*.006*od);
        vec3 ambient=environment_row(vec3(0,1,0),environment_layout.z+1.0)*interior_visibility(var_world);
        radiance=radiance*trans+ambient*(1.0-trans)*.55;
    }
    gl_FragColor=store_transparency(clamp(radiance,0.0,colour_pipeline.x>.5?65504.0:8.0)*alpha,alpha);
}
