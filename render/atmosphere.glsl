// Adapted from Claude-of-Duty src/sky/atmosphere.js (MIT).
// Lengths are megametres; medium coefficients match the reference.
uniform highp vec4 atmosphere_data[7];
#define atmo_key atmosphere_data[0]
#define atmo_irradiance atmosphere_data[1]
#define atmo_options atmosphere_data[2]
const float AT_PI=3.14159265359;
const vec3 AT_VIEW=vec3(0,6.3602,0);
float at_sphere(vec3 p,vec3 d,float r) {
    float b=dot(p,d),c=dot(p,p)-r*r,h=b*b-c;
    if(h<0.0) return -1.0;
    float a=-b-sqrt(h);return a>0.0?a:-b+sqrt(h);
}
void at_medium(vec3 p,out vec3 ray,out float mie,out vec3 ext) {
    float h=max(0.0,(length(p)-6.36)*1000.0);
    ray=vec3(5.802,13.558,33.1)*exp(-h/8.0);
    mie=3.996*atmo_options.x*exp(-h/1.2);
    ext=ray+vec3(mie+4.4*atmo_options.x*exp(-h/1.2))
        +vec3(.650,1.881,.085)*max(0.0,1.0-abs(h-25.0)/15.0);
}
vec3 at_transmittance(vec3 p,vec3 d) {
    if(at_sphere(p,d,6.36)>0.0) return vec3(0);
    float length_to_top=at_sphere(p,d,6.46);
    vec3 optical=vec3(0);
    // Quadratic spacing resolves the dense boundary layer at sunset.
    for(int i=0;i<16;i++) {
        float a=float(i)/16.0,b=float(i+1)/16.0;
        float start=a*a*length_to_top,end=b*b*length_to_top;
        vec3 ray,ext;float mie;
        at_medium(p+d*(start+end)*.5,ray,mie,ext);
        optical+=ext*(end-start);
    }
    return exp(-optical);
}
float at_hg(float c,float g) {
    float d=max(.0001,1.0+g*g-2.0*g*c);
    return (1.0-g*g)/(4.0*AT_PI*d*sqrt(d));
}
vec3 at_scatter_light(vec3 d,vec3 key,vec3 irradiance) {
    float end=at_sphere(AT_VIEW,d,6.46),ground=at_sphere(AT_VIEW,d,6.36);
    if(ground>0.0) end=min(end,ground);
    float c=dot(d,key);
    float phaseR=3.0/(16.0*AT_PI)*(1.0+c*c);
    float phaseM=3.0/(8.0*AT_PI)*(1.0-.64)/(2.0+.64)*(1.0+c*c)/pow(1.64-1.6*c,1.5);
    vec3 light=vec3(0),trans=vec3(1);
    for(int i=0;i<32;i++) {
        float a=float(i)/32.0,b=float(i+1)/32.0;
        float start=a*a*end,finish=b*b*end,dt=finish-start;
        vec3 p=AT_VIEW+d*(start+finish)*.5,ray,ext;float mie;
        at_medium(p,ray,mie,ext);
        vec3 beam=at_transmittance(p,key);
        // Bounded isotropic second-order fill; the full reference multiscatter
        // LUT is approximated here, while single scatter/ozone stay spectral.
        vec3 fill=(1.0-beam)*.018;
        vec3 source=(ray*(phaseR*beam+fill)+mie*(phaseM*beam+fill))*irradiance;
        vec3 segment=exp(-ext*dt);
        light+=trans*source*(1.0-segment)/max(ext,vec3(.000001));trans*=segment;
    }
    return light;
}

vec3 at_scatter(vec3 d) {
    vec3 result=vec3(0);
    if(atmosphere_data[5].r>.00001) result+=at_scatter_light(d,atmosphere_data[3].xyz,atmosphere_data[5].rgb);
    if(atmosphere_data[6].r>.00001) result+=at_scatter_light(d,atmosphere_data[4].xyz,atmosphere_data[6].rgb);
    return result;
}
