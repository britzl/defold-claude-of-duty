// Object/bind-space procedural detail. Derivative filtering fades each physical
// frequency before Nyquist; no time-dependent seeds or texture allocations.
uniform highp vec4 combat_features; // material detail, soft particles, decals, reserved
float combat_wave(float p) {
    float width=fwidth(p);
    return sin(p*6.2831853)*(1.0-smoothstep(.2,.65,width));
}
float combat_noise(vec3 p) {
    return sin(p.x+sin(p.z*1.7))*sin(p.y*.93+cos(p.z));
}
void combat_surface(vec3 p,vec3 local_normal,vec3 world_position,vec3 geometric,
    vec4 colour,out vec3 albedo,out float rough,out float metal,out vec3 n) {
    float kind=floor(colour.a+.001);
    albedo=linear_colour(colour.rgb);n=geometric;
    metal=kind<.5?.92:kind>6.5?.8:0.0;
    rough=kind<.5?.32:kind<1.5?.46:kind<2.5?.64:kind<3.5?.88:kind<4.5?.63:kind<5.5?.91:.86;
    if(combat_features.x<.5) return;
#ifdef VIEWMODEL_SURFACE
    if(kind>.5 && kind<1.5) rough=.58;
#endif
    vec3 axis=abs(local_normal);
    vec2 uv=axis.x>axis.y && axis.x>axis.z?p.zy:axis.y>axis.z?p.xz:p.xy;
    float grain=combat_noise(p*620.0)*(1.0-smoothstep(.25,.9,length(fwidth(p*620.0))));
    float weave=combat_wave(uv.x*520.0)*combat_wave(uv.y*520.0);
    float height=0.0;
    if(kind<1.5 || kind>6.5) {
        float brushed=combat_wave(uv.y*900.0+sin(uv.x*37.0)*.2);
        float scratch=pow(max(0.0,combat_wave(uv.x*135.0+sin(uv.y*31.0)*.13)),18.0);
        scratch*=smoothstep(.1,.7,combat_noise(p*45.0));
#ifdef VIEWMODEL_SURFACE
        // Chamfer wear is authored on the mesh, so broad panels stay coated.
        float wear=fract(colour.a)*2.0;
        scratch*=wear;
        if(kind>.5 && kind<1.5) {
            albedo=mix(albedo,vec3(.12),wear*.35);
            metal=wear*.35;
        }
#endif
        rough=clamp(rough+grain*.045+brushed*.025-scratch*.12,.22,.62);
        albedo*=1.0+grain*.055;
        if(kind>.5 && kind<1.5) { albedo=mix(albedo,vec3(.38),scratch*.45);metal=max(metal,scratch*.7); }
        height=(brushed*.4+scratch)*.000018;
    } else if((kind>2.5 && kind<3.5) || (kind>5.5 && kind<6.5)) {
        if(kind>5.5) {
            float camo=combat_noise(p*37.0)+combat_noise(p*79.0)*.35;
            albedo*=mix(.42,1.13,smoothstep(-.3,.30,camo));
        }
        albedo*=1.0+weave*.12+grain*.045;
#ifdef VIEWMODEL_SURFACE
        float fibres=combat_noise(p*180.0)*(1.0-smoothstep(.3,.9,length(fwidth(p*180.0))));
        albedo*=1.0+fibres*.18+weave*.1;
#endif
        rough=clamp(rough+weave*.045,.74,.98);
        height=weave*.000035;
#ifdef VIEWMODEL_SURFACE
        height+=weave*.00005;
#endif
    } else {
        albedo*=1.0+grain*(kind<4.5 && kind>3.5?.035:.09);
        rough=clamp(rough+grain*.045,.5,.98);
        height=grain*.000018;
    }
    // Surface gradient in world space follows rigid AND skinned geometry.
    vec3 dx=dFdx(world_position),dy=dFdy(world_position);
    vec3 rx=cross(dy,geometric),ry=cross(geometric,dx);
    float determinant=dot(dx,rx);
    if(abs(determinant)>1e-12)
        n=normalize(geometric-sign(determinant)*(dFdx(height)*rx+dFdy(height)*ry)/abs(determinant)*features.y);
}
