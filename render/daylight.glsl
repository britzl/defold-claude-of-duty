// One packed binding shared by all surface, sky and fog passes.
uniform highp vec4 daylight_data[7];
#define sun_direction daylight_data[0]
#define sun_radiance daylight_data[1]
#define sky_horizon daylight_data[2]
#define sky_zenith daylight_data[3]
#define ground_radiance daylight_data[4]
#define sun_shape daylight_data[5]

#define weather_data daylight_data[6]
