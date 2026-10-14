// Packed into one binding to stay below the Metal descriptor limit.
uniform highp vec4 daylight_data[6];
#define sun_direction daylight_data[0]
#define sun_radiance daylight_data[1]
#define sky_horizon daylight_data[2]
#define sky_zenith daylight_data[3]
#define ground_radiance daylight_data[4]
#define sun_shape daylight_data[5]
vec3 sky_environment(vec3 direction) {
    vec3 d=normalize(direction);
    float elevation=pow(max(d.y,0.0),.45);
    vec3 sky=mix(sky_horizon.rgb,sky_zenith.rgb,elevation);
    float sun=max(dot(d,normalize(sun_direction.xyz)),0.0);
    sky+=sun_radiance.rgb*sun_shape.x*pow(sun,sun_shape.z);
    return mix(ground_radiance.rgb,sky,smoothstep(-.12,.02,d.y));
}
vec3 sky_radiance(vec3 direction) {
    vec3 d=normalize(direction);
    float sun=max(dot(d,normalize(sun_direction.xyz)),0.0);
    // Direct GGX sunlight supplies the surface highlight. Keep the visible disc
    // out of IBL so it is not counted twice or undersampled in rough reflections.
    return sky_environment(d)+sun_radiance.rgb*sun_shape.y
        *smoothstep(sun_shape.w,mix(sun_shape.w,1.0,2.0/3.0),sun)*smoothstep(-.12,.02,d.y);
}
