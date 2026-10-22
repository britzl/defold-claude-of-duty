varying highp vec2 var_uv;
uniform highp vec4 bake_region; // normalized y offset, height, reuse clear scattering
uniform highp vec4 scattering_size; // dimensions, reciprocal dimensions
uniform highp sampler2D scattering_texture;
uniform highp sampler2D scattering_fine_texture;
#include "/render/radiance.glsl"
#include "/render/daylight.glsl"
#include "/render/atmosphere.glsl"
#include "/render/clouds.glsl"
void main() {
    vec2 uv=vec2(var_uv.x,bake_region.x+var_uv.y*bake_region.y);
    // Full-image loading and strip updates must integrate exactly the same ray.
    uv=(floor(uv*scattering_size.xy)+.5)*scattering_size.zw;
    float longitude=(uv.x*2.0-1.0)*AT_PI,latitude=(uv.y-.5)*AT_PI;
    vec3 d=vec3(cos(latitude)*sin(longitude),sin(latitude),cos(latitude)*cos(longitude));
    vec3 coarse,fine,encoded;
    if(bake_region.z>.5) {
        coarse=texture2D(scattering_texture,uv).rgb;
        fine=texture2D(scattering_fine_texture,uv).rgb;
        encoded=floor(coarse*255.0+.5)*256.0+floor(fine*255.0+.5);
    } else {
        // 16-bit log radiance in two portable RGBA8 attachments. The wide
        // range preserves moonlight; relative quantization error is <0.026%.
        encoded=floor(clamp((log2(max(at_scatter(d),vec3(exp2(-32.0))))+32.0)/48.0,0.0,1.0)*65535.0+.5);
        coarse=floor(encoded/256.0);
        fine=(encoded-coarse*256.0)/255.0;
        coarse/=255.0;
    }
    // Decode on misses too, so an addressed weather pose is independent of
    // cache state. Preserve the packed bytes on hits to avoid cumulative loss.
    vec3 sky=exp2(encoded*(48.0/65535.0)-32.0);
    vec4 cloud=at_clouds(d,sky);
    sky=mix(sky,cloud.rgb,cloud.a);
    sky=mix(ground_radiance.rgb,sky,smoothstep(-.035,.005,d.y));
    gl_FragData[0]=vec4(encode_radiance(sky),1.0-cloud.a);
    gl_FragData[1]=vec4(coarse,1.0);
    gl_FragData[2]=vec4(fine,1.0);
}
