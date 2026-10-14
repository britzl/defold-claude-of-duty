// Two static shell decks adapted from src/sky/clouds.js (MIT).
#include "/render/sky_noise.glsl"
float cloud_density(vec2 p) {
    float macro=clamp(.5+.5*(.42*sin(p.x*.09064+.7)*cos(p.y*.07282-.4)
        +.36*sin(p.x*.03806-p.y*.04598+1.9)+.30*cos(p.x*.019162+p.y*.024706-.6)),0.0,1.0);
    float coverage=.46*(.34+1.30*macro);
    vec2 warp=vec2(skVal2(p*.42),skVal2(p*.42+19.7))-.5;
    float n=skFbm2(p*.75+warp*1.6,4);
    float d=smoothstep(1.0-coverage,1.05-coverage*.34,n);
    return clamp(d-(1.0-d)*(.50-.50*skRidge2(p*3.2+warp*2.0,2)),0.0,1.0);
}
float cloud_shadow(vec2 p,vec3 key) {
    if(atmo_options.z<.5 || key.y<=0.0) return 1.0;
    vec2 deck=p*.001+key.xz*(1.5/max(.05,key.y));
    return exp(-cloud_density(deck)*1.9*2.1);
}
vec4 at_clouds(vec3 d,vec3 ambient) {
    if(d.y<-.008 || atmo_options.z<.5) return vec4(0);
    vec3 key=atmo_key.xyz;float c=dot(d,key);
    float high=at_sphere(AT_VIEW,d,6.3678);
    vec2 p=d.xz*high*1000.0;
    // Decorrelated, bounded bearings and broken fibres avoid a radial starburst.
    float angle=.24+(skVal2(p*.135)-.5)*1.1;
    mat2 turn=mat2(cos(angle),sin(angle),-sin(angle),cos(angle));
    vec2 q=turn*p;
    float fibres=skFbm2(q*vec2(.4,1.4),2);
    float high_density=smoothstep(.48,.72,skFbm2(p*.32+137.4,3))*(.35+fibres);
    float high_alpha=high_density*.48*(1.0-smoothstep(18.0,45.0,high*1000.0));
    high_alpha*=1.0-smoothstep(.15,.8,max(length(dFdx(p)),length(dFdy(p))));
    high_alpha*=1.0-.66*smoothstep(.55,.85,d.y);
    vec3 high_light=at_transmittance(vec3(0,6.3678,0),key)*atmo_irradiance.rgb;
    vec3 high_colour=high_light*(at_hg(c,.74)*3.2+.60)/AT_PI+ambient*.85;
    float low=at_sphere(AT_VIEW,d,6.3615);
    p=d.xz*low*1000.0;
    float footprint=max(length(dFdx(p)),length(dFdy(p)));
    float base=cloud_density(p);
    p+=d.xz*(.85*base/max(.10,d.y));
    float density=max(base*.55,cloud_density(p));
    vec2 step2=normalize(key.xz+vec2(.0001))*(.20/max(.12,abs(key.y)));
    float lit=exp(-(cloud_density(p+step2)+.7*cloud_density(p+step2*2.4)+.4*cloud_density(p+step2*4.6))*1.9*2.1);
    float thick=density*1.9*mix(1.0,1.7,.09/(abs(d.y)+.09));
    float low_alpha=(1.0-exp(-thick*3.4))*(1.0-smoothstep(10.0,35.0,low*1000.0))*(1.0-smoothstep(.12,.65,footprint));
    vec3 low_light=at_transmittance(vec3(0,6.3615,0),key)*atmo_irradiance.rgb;
    vec3 low_colour=low_light*(lit*(.62+at_hg(c,.62)*4.0)*(1.0-exp(-thick*5.5))+.12)/AT_PI+ambient*.65;
    float alpha=low_alpha+high_alpha*(1.0-low_alpha);
    return vec4((low_colour*low_alpha+high_colour*high_alpha*(1.0-low_alpha))/max(alpha,.0001),alpha);
}
