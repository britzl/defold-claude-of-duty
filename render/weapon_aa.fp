varying highp vec2 var_uv;
uniform highp sampler2D source_texture;
uniform highp vec4 aa_params;
#include "/render/radiance.glsl"
vec4 linear_texel(vec2 uv) {
    vec4 c=texture2D(source_texture,uv);
    return vec4(decode_radiance(c.rgb),c.a);
}
vec4 sample_weapon(vec2 uv) {
    // Decode premultiplied radiance before interpolation; retain the encoded
    // path's dark-tone precision while filtering transparent flashes correctly.
    if(colour_pipeline.x<.5) {
        vec2 p=aa_params.xy,base=floor(uv/p-.5),f=fract(uv/p-.5);
        return mix(mix(linear_texel((base+vec2(.5,.5))*p),linear_texel((base+vec2(1.5,.5))*p),f.x),
                   mix(linear_texel((base+vec2(.5,1.5))*p),linear_texel((base+vec2(1.5,1.5))*p),f.x),f.y);
    }
    return linear_texel(uv);
}
float edge_value(vec4 c) { return max(c.a,dot(c.rgb,vec3(.2126,.7152,.0722))); }
void main() {
    vec2 p=aa_params.xy;
    vec4 centre=sample_weapon(var_uv);
    float nw=edge_value(sample_weapon(var_uv+vec2(-1,1)*p));
    float ne=edge_value(sample_weapon(var_uv+vec2(1,1)*p));
    float sw=edge_value(sample_weapon(var_uv+vec2(-1,-1)*p));
    float se=edge_value(sample_weapon(var_uv+vec2(1,-1)*p));
    float m=edge_value(centre),low=min(m,min(min(nw,ne),min(sw,se))),high=max(m,max(max(nw,ne),max(sw,se)));
    vec4 result=centre;
    if(high-low>max(.0312,high*.125)) {
        vec2 direction=vec2(-((nw+ne)-(sw+se)),(nw+sw)-(ne+se));
        float reduce=max((nw+ne+sw+se)*.03125,.0078125);
        direction=clamp(direction/(min(abs(direction.x),abs(direction.y))+reduce),-4.0,4.0)*p;
        vec4 a=(sample_weapon(var_uv-direction/6.0)+sample_weapon(var_uv+direction/6.0))*.5;
        vec4 b=a*.5+(sample_weapon(var_uv-direction*.5)+sample_weapon(var_uv+direction*.5))*.25;
        float l=edge_value(b);result=(l<low || l>high)?a:b;
    }
    gl_FragColor=vec4(encode_radiance(result.rgb),result.a);
}
