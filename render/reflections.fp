// Bounded view-space ray march with crossing refinement and confidence fallback.
varying highp vec2 var_uv;
uniform highp sampler2D source_texture;
uniform lowp sampler2D depth_normal_texture;
uniform lowp sampler2D reflection_surface_texture;
uniform lowp sampler2D reflection_weight_texture;
uniform highp mat4 reflection_view;
uniform highp mat4 reflection_inverse_view;
uniform highp vec4 screen_projection;
uniform highp vec4 reflection_params; // inverse size, diagnostic, filtered IBL
#include "/render/radiance.glsl"
#include "/render/depth_normal.glsl"
#include "/render/environment_sampling.glsl"
vec2 project_point(vec3 p) {return (p.xy/max(-p.z,.001)*screen_projection.xy-screen_projection.zw)*.5+.5;}
float edge_confidence(vec2 uv) {return smoothstep(0.0,.08,min(min(uv.x,uv.y),min(1.0-uv.x,1.0-uv.y)));}
void main() {
    vec3 base=decode_radiance(texture2D(source_texture,var_uv).rgb);
    vec4 surface=texture2D(reflection_surface_texture,var_uv);
    vec4 depth=texture2D(depth_normal_texture,var_uv);
    vec3 weight=texture2D(reflection_weight_texture,var_uv).rgb;
    float roughness=surface.b,confidence=0.0;
    vec3 radiance=base;
    if(surface.a>.5 && roughness<.6 && depth_covered(depth) && max(weight.r,max(weight.g,weight.b))>.003) {
        vec3 p=view_position(var_uv,unpack_view_depth(depth.rg),screen_projection);
        vec3 n=(reflection_view*vec4(unpack_view_normal(surface.rg),0)).xyz;
        vec3 direction=reflect(normalize(p),normalize(n));
        vec3 origin=p+n*max(.025,-p.z*.0006);
        float previous=0.0;
        vec2 hit=var_uv;
        for(int i=1;i<=48;i++) {
            float f=float(i)/48.0,t=.06+24.0*f*f;
            vec3 q=origin+direction*t;
            if(q.z>-.1) break;
            vec2 uv=project_point(q);
            if(min(uv.x,uv.y)<=0.0 || max(uv.x,uv.y)>=1.0) break;
            vec4 sample_depth=texture2D(depth_normal_texture,uv);
            float z=unpack_view_depth(sample_depth.rg);
            float gap=-q.z-z;
            if(depth_covered(sample_depth) && gap>=0.0) {
                float low=previous,high=t;
                for(int j=0;j<5;j++) {
                    float middle=(low+high)*.5;
                    vec3 m=origin+direction*middle;vec2 mu=project_point(m);
                    float mz=unpack_view_depth(texture2D(depth_normal_texture,mu).rg);
                    if(-m.z>mz) high=middle;else low=middle;
                }
                q=origin+direction*high;hit=project_point(q);
                sample_depth=texture2D(depth_normal_texture,hit);z=unpack_view_depth(sample_depth.rg);
                gap=-q.z-z;
                float thickness=.10+z*.003;
                if(depth_covered(sample_depth) && gap>=-.02 && gap<thickness && high>.12) {
                    confidence=edge_confidence(hit)*edge_confidence(var_uv);
                    confidence*=1.0-smoothstep(.35,.6,roughness);
                    confidence*=1.0-smoothstep(18.0,24.0,high);
                    confidence*=smoothstep(-.1,.2,dot(unpack_view_normal(sample_depth.ba),-direction));
                }
                // First crossing owns the visibility decision. A rejected thin
                // edge falls back to the environment; never trace through it.
                break;
            }
            previous=t;
        }
        if(confidence>0.0) {
            // Small roughness footprint; reject taps crossing a depth edge.
            vec3 reflected=decode_radiance(texture2D(source_texture,hit).rgb);float total=1.0;
            float hit_depth=unpack_view_depth(texture2D(depth_normal_texture,hit).rg);
            for(int i=0;i<4;i++) {
                vec2 axis=i==0?vec2(1,0):i==1?vec2(-1,0):i==2?vec2(0,1):vec2(0,-1);
                vec2 uv=hit+axis*reflection_params.xy*(1.0+roughness*roughness*24.0);
                float z=unpack_view_depth(texture2D(depth_normal_texture,uv).rg);
                float valid=1.0-smoothstep(.05,.2,abs(z-hit_depth));
                reflected+=decode_radiance(texture2D(source_texture,uv).rgb)*valid;total+=valid;
            }
            reflected/=total;
            vec3 world_ray=(reflection_inverse_view*vec4(direction,0)).xyz;
            vec3 fallback=environment_specular(world_ray,reflection_params.w>.5?roughness:0.0);
            // Replace the existing environment term, preserving BRDF/indoor/AO/fog weights.
            radiance=max(vec3(0),base+(reflected-fallback)*weight*confidence);
        }
    }
    gl_FragColor=reflection_params.z>.5?vec4(vec3(confidence),1):vec4(encode_radiance(radiance),1);
}
