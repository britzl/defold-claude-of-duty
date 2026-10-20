varying highp vec2 var_uv;
uniform highp vec4 bake_region; // normalized y offset, height
#include "/render/radiance.glsl"
#include "/render/daylight.glsl"
#include "/render/atmosphere.glsl"
#include "/render/clouds.glsl"
void main() {
    float longitude=(var_uv.x*2.0-1.0)*AT_PI,latitude=(bake_region.x+var_uv.y*bake_region.y-.5)*AT_PI;
    vec3 d=vec3(cos(latitude)*sin(longitude),sin(latitude),cos(latitude)*cos(longitude));
    vec3 sky=at_scatter(d);
    vec4 cloud=at_clouds(d,sky);
    sky=mix(sky,cloud.rgb,cloud.a);
    sky=mix(ground_radiance.rgb,sky,smoothstep(-.035,.005,d.y));
    gl_FragColor=vec4(encode_radiance(sky),1.0-cloud.a);
}
