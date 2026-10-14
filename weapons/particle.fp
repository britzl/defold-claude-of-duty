varying highp vec3 var_world;
varying mediump vec3 var_normal;
varying mediump vec3 var_view_normal;
varying highp float var_depth;
varying mediump vec2 var_uv;
uniform highp vec4 particle; // kind (smoke/flash/decal), opacity, seed, reserved
uniform lowp vec4 tint;
uniform highp vec4 glass_screen;
uniform highp vec4 combat_features;
uniform lowp sampler2D depth_normal_texture;
#include "/render/lighting.glsl"
#include "/render/depth_normal.glsl"
void main() {
    vec4 scene=texture2D(depth_normal_texture,gl_FragCoord.xy*glass_screen.xy+glass_screen.zw);
    float gap=depth_covered(scene)?unpack_view_depth(scene.rg)-var_depth:500.0;
    float r=length(var_uv),alpha=0.0;
    vec3 radiance;
    if(particle.x>1.5) {
        if(combat_features.z<.5 || !depth_covered(scene) || abs(gap)>.025 ||
            dot(normalize(var_view_normal),unpack_view_normal(scene.ba))<.8) discard;
        float angle=atan(var_uv.y,var_uv.x);
        float edge=r*(1.0+.12*sin(angle*9.0+particle.z*18.0));
        float rim=smoothstep(.19,.35,edge)*(1.0-smoothstep(.4,.95,edge));
        alpha=(1.0-smoothstep(.28,.9,edge))*.94;
        vec3 albedo=linear_colour(tint.rgb)*mix(.16,1.5,rim);
        radiance=lighting(albedo,.92,0.0,1.0,var_world,normalize(var_normal),normalize(var_normal));
    } else {
        if(gap<=0.0) discard;
        float noise=sin(var_uv.x*12.0+particle.z*19.0)*sin(var_uv.y*13.0+sin(var_uv.x*5.0));
        if(particle.x>.5) {
            alpha=pow(max(0.0,1.0-r),2.0);
            alpha=max(alpha,(1.0-smoothstep(.035,.16,abs(var_uv.x*var_uv.y)))*(1.0-smoothstep(.2,.95,r))*.55);
            radiance=mix(vec3(18,9,2),vec3(32,27,15),pow(max(0.0,1.0-r*2.0),2.0));
        } else {
            alpha=pow(max(0.0,1.0-r*r),2.0)*(.8+noise*.2);
            vec3 n=normalize(var_normal);
            // Wrap illumination for a small volume: no metallic highlights.
            vec3 ambient=environment_row(vec3(0,1,0),environment_layout.z+1.0)*interior_visibility(var_world);
            float sun=shadow_visibility(var_world,n);
            radiance=linear_colour(tint.rgb)*(ambient+sun_radiance.rgb*sun*.30);
        }
        if(combat_features.y>.5) alpha*=smoothstep(0.0,particle.x>.5?.025:.18,gap);
        alpha*=smoothstep(.04,.16,var_depth);
    }
    alpha*=particle.y;
    if(alpha<.001) discard;
    if(features.w>.5) {
        vec3 ray=var_world-eye_position.xyz;float distance_to_eye=length(ray);
        float slope=ray.y*.16,base=exp(clamp(-eye_position.y*.16,-40.0,8.0));
        float od=base*distance_to_eye*(abs(slope)<.0001?1.0:(1.0-exp(clamp(-slope,-40.0,40.0)))/slope);
        vec3 trans=exp(-vec3(.88,.96,1.08)*.006*od);
        vec3 ambient=environment_row(vec3(0,1,0),environment_layout.z+1.0)*interior_visibility(var_world);
        radiance=radiance*trans+ambient*(1.0-trans)*.55;
    }
    // Same premultiplied linear representation as glass, including RGBA8.
    gl_FragColor=vec4(clamp(radiance/(colour_pipeline.x>.5?1.0:8.0),0.0,colour_pipeline.x>.5?65504.0:1.0)*alpha,alpha);
}
