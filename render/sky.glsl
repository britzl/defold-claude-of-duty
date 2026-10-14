#include "/render/daylight.glsl"
uniform highp sampler2D sky_texture;
uniform highp vec4 atmosphere_data[5];
vec2 sky_uv(vec3 d) {
    return vec2(atan(d.x,d.z)/6.28318530718+.5,asin(clamp(d.y,-1.0,1.0))/3.14159265359+.5);
}
vec3 sky_environment(vec3 direction) {
    return decode_radiance(texture2D(sky_texture,sky_uv(normalize(direction))).rgb);
}
vec3 sky_radiance(vec3 direction) {
    vec3 d=normalize(direction),key=normalize(sun_direction.xyz);
    vec4 sky=texture2D(sky_texture,sky_uv(d));
    vec3 result=decode_radiance(sky.rgb);
    float cosine=dot(d,key);
    float radius=atmosphere_data[2].y>.5?.0065:.00465;
    float angle=acos(clamp(cosine,-1.0,1.0));
    float aa=max(fwidth(angle),.00005);
    float disc=1.0-smoothstep(radius-aa,radius+aa,angle);
    float limb=sqrt(max(0.0,1.0-angle*angle/(radius*radius)));
    float intensity=atmosphere_data[2].y>.5?5.0:24.0;
    if(atmosphere_data[2].y>.5) {
        vec3 tangent=normalize(cross(vec3(0,1,0),key)),up=cross(key,tangent);
        vec2 xy=vec2(dot(d,tangent),dot(d,up))/radius;
        vec3 normal=tangent*xy.x+up*xy.y-key*limb;
        intensity*=max(0.0,dot(normal,atmosphere_data[3].xyz))*(.82+.18*sin(xy.x*31.0)*sin(xy.y*23.0));
        // Static directional star field, faded through clouds and near the horizon.
        vec2 grid=sky_uv(d)*vec2(1800,900),cell=floor(grid);
        float hash=fract(sin(dot(cell,vec2(127.1,311.7)))*43758.5453);
        float star=(1.0-smoothstep(.05,.22,length(fract(grid)-.5)))*step(.998,hash);
        result+=vec3(.14,.17,.23)*star*sky.a*smoothstep(.02,.18,d.y);
    }
    result+=sun_radiance.rgb*intensity*(.4+.6*limb)*disc*sky.a*smoothstep(-.01,.01,d.y);
    return result;
}
