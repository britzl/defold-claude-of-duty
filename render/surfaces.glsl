// Bounded adaptations of the reference surface recipes: plaster mottling,
// asphalt aggregate, wood fibres, worn metal and woven cloth. Periodic noise
// keeps opposite edges continuous; frequencies stay below the bake's Nyquist.
float surface_hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7))) * 43758.5453); }
float periodic_noise(vec2 uv, vec2 cells)
{
    vec2 p=uv*cells, i=floor(p), f=fract(p);
    f=f*f*(3.0-2.0*f);
    return mix(mix(surface_hash(mod(i,cells)),surface_hash(mod(i+vec2(1,0),cells)),f.x),
        mix(surface_hash(mod(i+vec2(0,1),cells)),surface_hash(mod(i+vec2(1,1),cells)),f.x),f.y);
}
void surface_sample(vec2 uv, float kind, out vec3 albedo, out float height, out vec3 packed)
{
    float macro=periodic_noise(uv,vec2(4.0));
    float fine=periodic_noise(uv,vec2(48.0));
    float mid=periodic_noise(uv,vec2(16.0));
    float variation=0.78+0.22*macro+0.05*fine;
    float roughness=0.82+0.12*fine, metal=0.0, ao=1.0;
    height=0.45+0.16*mid+0.045*fine;
    if (kind>0.5 && kind<1.5) {
        float aggregate=smoothstep(0.45,0.73,fine);
        height=0.4+aggregate*0.18+mid*0.045;
        variation=0.72+macro*0.20+aggregate*0.08;
        roughness=0.74+0.20*mid;
        ao=0.88+0.12*aggregate;
    } else if (kind>1.5 && kind<2.5) {
        float grain=periodic_noise(uv,vec2(48.0,4.0));
        float rings=sin(uv.x*75.398+periodic_noise(uv,vec2(4.0))*3.0)*0.5+0.5;
        height=0.42+grain*0.12+rings*0.035;
        variation=0.64+grain*0.25+rings*0.10;
        roughness=0.64+0.22*grain;
        ao=0.88+0.12*grain;
    } else if (kind>2.5 && kind<3.5) {
        float scratch=periodic_noise(uv,vec2(4.0,64.0));
        float rust=smoothstep(0.63,0.84,macro);
        height=0.5+scratch*0.012+rust*0.10;
        variation=0.82+scratch*0.14-rust*0.20;
        roughness=mix(0.28+0.16*scratch,0.88,rust);
        metal=1.0-rust;
    } else if (kind>3.5) {
        float weave=sin(uv.x*201.062)*sin(uv.y*201.062)*0.5+0.5;
        height=0.5+weave*0.04;
        variation=0.84+macro*0.12+weave*0.04;
        roughness=0.94;
    }
    albedo=vec3(variation);
    packed=vec3(roughness,metal,ao);
}
