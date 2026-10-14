varying highp vec2 var_uv;
uniform highp sampler2D scene_texture;
uniform highp sampler2D weapon_texture;
uniform highp sampler2D bloom_texture;
uniform lowp sampler2D debug_texture;
uniform highp vec4 environment_debug;
uniform highp vec4 atlas_window;
uniform highp sampler2D exposure_texture;
uniform highp sampler2D grade_texture;
uniform highp vec4 photo; // grade, sharpen, vignette, grain
uniform highp vec4 photo_screen; // inverse resolution, presentation seconds
uniform highp vec4 post; // exposure, bloom strength, debug view, atlas half (0=all,1=lower,2=upper)
#include "/render/radiance.glsl"
#include "/render/agx.glsl"
#include "/render/photographic.glsl"
#include "/render/depth_normal.glsl"
#include "/render/environment_sampling.glsl"
vec3 tone_map(vec3 c) {
    return display_colour(agx_neutral(c*post.x));
}
vec3 combined(vec2 uv) {
    vec4 weapon=texture2D(weapon_texture,uv);
    return decode_radiance(texture2D(scene_texture,uv).rgb)*(1.0-weapon.a)+decode_radiance(weapon.rgb);
}
vec3 grade(vec3 colour) {
    vec3 p=clamp(colour,0.0,1.0)*32.0;
    float slice=floor(p.b),next_slice=min(slice+1.0,32.0);
    vec2 uv=vec2((slice*33.0+p.r+.5)/1089.0,(p.g+.5)/33.0);
    vec2 next_uv=vec2((next_slice*33.0+p.r+.5)/1089.0,uv.y);
    return mix(texture2D(grade_texture,uv).rgb,texture2D(grade_texture,next_uv).rgb,fract(p.b));
}
void main() {
    if(post.z>23.5) {
        gl_FragColor=vec4(texture2D(grade_texture,var_uv).rgb,1);
    } else if(post.z>22.5) {
        vec4 data=texture2D(exposure_texture,vec2(.5));
        gl_FragColor=vec4(photo_unpack(data.rg),photo_unpack(data.ba),0,1);
    } else if(post.z>21.5) {
        gl_FragColor=vec4(display_colour(agx_neutral(decode_radiance(texture2D(bloom_texture,var_uv).rgb))),1);
    } else if(post.z>19.5) {
        gl_FragColor=vec4(tone_map(decode_radiance(texture2D(scene_texture,var_uv).rgb)),1);
    } else if(post.z>17.5 && post.z<18.5) {
        vec2 d=texture2D(debug_texture,var_uv).rg;gl_FragColor=vec4(vec3(d.r+d.g/255.0),1);
    } else if(post.z>14.5) {
        gl_FragColor=vec4(texture2D(scene_texture,var_uv).rgb,1.0);
    } else if(post.z>9.5) {
        vec4 data=texture2D(debug_texture,var_uv);
        vec3 value;
        if(post.z<10.5) value=depth_covered(data)?vec3(log2(1.0+unpack_view_depth(data.rg))/DEPTH_LOG_RANGE):vec3(1.0);
        else if(post.z<11.5) value=depth_covered(data)?unpack_view_normal(data.ba)*.5+.5:vec3(0.0);
        else if(post.z<12.5) value=vec3(data.r);
        else if(post.z<13.5) value=vec3(data.g);
        else value=vec3(data.r,data.g,1.0);
        gl_FragColor=vec4(value,1.0);
    } else if (post.z>6.5) {
        vec3 value=texture2D(environment_texture,var_uv).rgb;
        bool lut=var_uv.y>(environment_layout.w-1.0)/environment_layout.w;
        gl_FragColor=vec4(lut?value:tone_map(decode_radiance(value)),1);
    } else if (post.z>5.5) {
        // Bottom: radiance / 64. Middle: shared AgX. Top: transfer functions,
        // linear filtering across 0.18/1, hardware blending, layer mix, alpha.
        vec3 source=decode_radiance(texture2D(scene_texture,var_uv).rgb);
        vec3 value;
        if (var_uv.y<1.0/3.0) value=source/64.0;
        else if (var_uv.y<2.0/3.0) value=tone_map(source);
        else if (var_uv.x<0.125) value=display_colour(vec3(0.0031308));
        else if (var_uv.x<0.25) value=linear_colour(vec3(0.04045));
        else if (var_uv.x<0.375) value=display_colour(vec3(0.18));
        else if (var_uv.x<0.5) value=linear_colour(vec3(0.5));
        else if (var_uv.x<0.625) value=decode_radiance(texture2D(scene_texture,vec2(0.5,0.5)).rgb);
        else if (var_uv.x<0.75) value=decode_radiance(texture2D(scene_texture,vec2(0.9375,0.5)).rgb)/64.0;
        else if (var_uv.x<0.875) {
            vec4 weapon=texture2D(weapon_texture,vec2(0.5));
            value=mix(decode_radiance(texture2D(scene_texture,vec2(0.6875,0.5)).rgb),decode_radiance(weapon.rgb),weapon.a)/64.0;
        } else value=vec3(texture2D(weapon_texture,vec2(0.5)).a);
        gl_FragColor=vec4(value,1.0);
    } else if (post.z>4.5) {
        float longitude=(var_uv.x*2.0-1.0)*3.14159265;
        float latitude=(var_uv.y-0.5)*3.14159265;
        vec3 d=vec3(cos(latitude)*sin(longitude),sin(latitude),cos(latitude)*cos(longitude));
        gl_FragColor=vec4(tone_map(environment_row(d,environment_debug.x)),1.0);
    } else if (post.z>0.5) {
        vec2 uv=atlas_window.xy+var_uv*atlas_window.zw;
        if(post.z<3.5 && post.w>0.5) uv.y=uv.y*0.5+(post.w>1.5?0.5:0.0);
        vec3 data=texture2D(debug_texture,uv).rgb;
        if (post.z>3.5) data=vec3(data.r+data.g/255.0);
        gl_FragColor=vec4(data,1.0);
    } else {
        vec3 hdr=combined(var_uv);
        if(photo.y>.001) {
            float lc=photo_luma(hdr);
            float a=photo_luma(combined(var_uv+vec2(photo_screen.x,0)));
            float b=photo_luma(combined(var_uv-vec2(photo_screen.x,0)));
            float c=photo_luma(combined(var_uv+vec2(0,photo_screen.y)));
            float d=photo_luma(combined(var_uv-vec2(0,photo_screen.y)));
            float lo=min(lc,min(min(a,b),min(c,d))),hi=max(lc,max(max(a,b),max(c,d)));
            float contrast=(hi-lo)/(hi+lo+.02);
            float amount=photo.y*(1.0-clamp(contrast*1.6,0.0,1.0))*smoothstep(.004,.03,lc);
            float sharpened=clamp(lc+(lc-(a+b+c+d)*.25)*amount,lo,hi);
            hdr*=clamp(sharpened/max(lc,.0001),.8,1.2);
        }
        hdr*=post.x*photo_exposure(texture2D(exposure_texture,vec2(.5)));
        hdr+=decode_radiance(texture2D(bloom_texture,var_uv).rgb)*post.y;
        vec2 delta=var_uv-.5;
        float falloff=pow(1.0/(1.0+dot(delta,delta)*2.4),2.0);
        hdr*=mix(1.0,falloff,photo.z);
        vec3 colour=display_colour(agx_neutral(hdr));
        colour=mix(colour,grade(colour),photo.x);
        float dither=fract(52.9829189*fract(dot(gl_FragCoord.xy,vec2(.06711056,.00583715))));
        float grain=fract(52.9829189*fract(dot(gl_FragCoord.xy+floor(photo_screen.z*30.0)*vec2(37,71),vec2(.06711056,.00583715))))-.5;
        colour+=grain*photo.w*(.35+.65*smoothstep(0.0,.30,photo_luma(colour)));
        gl_FragColor=vec4(clamp(colour+(dither-.5)/255.0,0.0,1.0),1);
    }
}
