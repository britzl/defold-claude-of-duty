// Shared world-space deck, in kilometres. Wind is 4.2 m/s at bearing .7.
// weather_data is packed in daylight_data to stay within Metal buffer bindings.
#include "/render/sky_noise.glsl"
float cloud_density(vec2 p) {
    float macro=clamp(.5+.5*(.42*sin(p.x*.09064+.7)*cos(p.y*.07282-.4)
        +.36*sin(p.x*.03806-p.y*.04598+1.9)+.30*cos(p.x*.019162+p.y*.024706-.6)),0.0,1.0);
    float coverage=.36*(.28+1.38*macro);
    vec2 warp=vec2(skVal2(p*.72),skVal2(p*.72+19.7))-.5;
    // Smaller separated banks leave sunlit gaps in the default street view.
    // Sky, fog and surface shadows evaluate this same drifting density field.
    float n=skFbm2(p*1.35+warp*.8+vec2(11.6,7.3),4);
    float d=smoothstep(1.0-coverage,1.05-coverage*.34,n);
    return clamp(d-(1.0-d)*(.50-.50*skRidge2(p*5.5+warp*2.0,2)),0.0,1.0);
}
float cloud_shadow(vec2 p,vec3 key) {
    if(weather_data.w<.5 || key.y<=0.0) return 1.0;
    vec2 deck=p*.001+key.xz*(1.5/max(.05,key.y))+weather_data.xy;
    return exp(-cloud_density(deck)*1.9*1.6);
}
