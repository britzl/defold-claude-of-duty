varying highp vec2 var_uv;
// Generated 33^3 reference grade in a bilinear-safe, blue-slice 2D LUT.
float curve(float x) {
    float c=.5*pow(max(x,0.0)/.5,1.28);
    float norm=1.0-exp(-(.5*pow(2.0,1.28)-.60)/1.20);
    if(c>.60) c=.60+.40*(1.0-exp(-(c-.60)/1.20))/norm;
    return .008+.992*clamp(c,0.0,1.0);
}
void main() {
    vec2 p=floor(var_uv*vec2(1089.0,33.0));
    vec3 c=vec3(mod(p.x,33.0),p.y,floor(p.x/33.0))/32.0;
    c=pow(max(c*vec3(1.0,.995,.985)+vec3(-.004,-.002,.004),vec3(0)),vec3(1.0,1.005,1.02));
    float l=dot(c,vec3(.2126,.7152,.0722));
    c+=vec3(-.001,.006,.022)*pow(1.0-min(1.0,l),2.2)+vec3(.030,.014,-.006)*pow(min(1.0,l),2.0);
    l=dot(c,vec3(.2126,.7152,.0722));
    c=mix(vec3(l),c,1.20);
    c=mix(c,vec3(l),.10*pow(clamp(l,0.0,1.0),3.0));
    gl_FragColor=vec4(curve(c.r),curve(c.g),curve(c.b),1);
}
