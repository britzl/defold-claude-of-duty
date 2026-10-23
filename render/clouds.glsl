// Two drifting shell decks adapted from src/sky/clouds.js (MIT).
#include "/render/cloud_density.glsl"
vec4 at_clouds(vec3 d,vec3 ambient) {
    if(d.y<-.008 || atmo_options.z<.5) return vec4(0);
    vec3 key=atmo_key.xyz;float c=dot(d,key);
    float high=at_sphere(AT_VIEW,d,6.3678);
    vec2 p=d.xz*high*1000.0+weather_data.xy*1.4;
    // Decorrelated, bounded bearings and broken fibres avoid a radial starburst.
    float angle=.24+(skVal2(p*.135)-.5)*1.1;
    mat2 turn=mat2(cos(angle),sin(angle),-sin(angle),cos(angle));
    vec2 q=turn*p;
    float fibres=skFbm2(q*vec2(.4,1.4),2);
    float high_density=smoothstep(.53,.76,skFbm2(p*.32+137.4,3))*(.35+fibres);
    float high_alpha=high_density*.28*(1.0-smoothstep(18.0,45.0,high*1000.0));
    high_alpha*=1.0-smoothstep(.15,.8,max(length(dFdx(p)),length(dFdy(p))));
    high_alpha*=1.0-.66*smoothstep(.55,.85,d.y);
    vec3 high_light=at_transmittance(vec3(0,6.3678,0),key)*atmo_irradiance.rgb;
    vec3 high_colour=high_light*(at_hg(c,.74)*3.2+.60)/AT_PI+ambient*.85;
    float low=at_sphere(AT_VIEW,d,6.3615);
    p=d.xz*low*1000.0+weather_data.xy;
    float footprint=max(length(dFdx(p)),length(dFdy(p)));
    float base=cloud_density(p);
    p+=d.xz*(.85*base/max(.10,d.y));
    float density=max(base*.55,cloud_density(p));
    vec2 step2=normalize(key.xz+vec2(.0001))*(.20/max(.12,abs(key.y)));
    float lit=exp(-(cloud_density(p+step2)+.7*cloud_density(p+step2*2.4)+.4*cloud_density(p+step2*4.6))*1.9*2.1);
    float thick=density*1.9*mix(1.0,1.7,.09/(abs(d.y)+.09));
    float low_alpha=(1.0-exp(-thick*3.4))*(1.0-smoothstep(10.0,35.0,low*1000.0))*(1.0-smoothstep(.12,.65,footprint));
    vec3 low_light=at_transmittance(vec3(0,6.3615,0),key)*atmo_irradiance.rgb;
    vec3 low_colour=low_light*(lit*(.62+at_hg(c,.62)*4.0)*(1.0-exp(-thick*5.5))+.18)/AT_PI+ambient*.85;
    float alpha=low_alpha+high_alpha*(1.0-low_alpha);
    return vec4((low_colour*low_alpha+high_colour*high_alpha*(1.0-low_alpha))/max(alpha,.0001),alpha);
}
