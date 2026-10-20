#include "/render/daylight.glsl"
uniform highp sampler2D sky_texture;
uniform highp vec4 atmosphere_data[7];
vec2 sky_uv(vec3 d) {
    return vec2(atan(d.x,d.z)/6.28318530718+.5,asin(clamp(d.y,-1.0,1.0))/3.14159265359+.5);
}
vec3 sky_environment(vec3 direction) {
    return decode_radiance(texture2D(sky_texture,sky_uv(normalize(direction))).rgb);
}
float sky_disc(vec3 d,vec3 key,float radius,out float limb) {
    float angle=acos(clamp(dot(d,key),-1.0,1.0));
    float aa=max(fwidth(angle),.00005);
    limb=sqrt(max(0.0,1.0-angle*angle/(radius*radius)));
    return (1.0-smoothstep(radius-aa,radius+aa,angle))*smoothstep(-.01,.01,d.y);
}
vec3 sky_radiance(vec3 direction) {
    vec3 d=normalize(direction);
    vec4 sky=texture2D(sky_texture,sky_uv(d));
    vec3 result=decode_radiance(sky.rgb);
    float limb;
    float disc=sky_disc(d,normalize(atmosphere_data[3].xyz),.00465,limb);
    result+=sun_shape.rgb*24.0*(.4+.6*limb)*disc*sky.a;
    vec3 key=normalize(atmosphere_data[4].xyz);
    disc=sky_disc(d,key,.0065,limb);
    vec3 tangent=normalize(cross(vec3(0,1,0),key)),up=cross(key,tangent);
    vec2 xy=vec2(dot(d,tangent),dot(d,up))/.0065;
    vec3 normal=tangent*xy.x+up*xy.y-key*limb;
    float intensity=5.0*max(0.0,dot(normal,atmosphere_data[3].xyz))*(.82+.18*sin(xy.x*31.0)*sin(xy.y*23.0));
    result+=sky_horizon.rgb*intensity*(.4+.6*limb)*disc*sky.a;
    vec2 grid=sky_uv(d)*vec2(1800,900),cell=floor(grid);
    float hash=fract(sin(dot(cell,vec2(127.1,311.7)))*43758.5453);
    float star=(1.0-smoothstep(.05,.22,length(fract(grid)-.5)))*step(.998,hash);
    result+=vec3(.14,.17,.23)*star*sky.a*smoothstep(.02,.18,d.y)*sky_horizon.w;
    return result;
}
