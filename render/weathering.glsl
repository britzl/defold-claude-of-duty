// Deterministic surface-anchored variation. Adapted from the reference material
// layering; see THIRD_PARTY_NOTICES.md. No clocks, camera noise or gameplay RNG.
float weather_hash(vec2 p) {
    vec3 q=fract(vec3(p.xyx)*0.1031);q+=dot(q,q.yzx+33.33);
    return fract((q.x+q.y)*q.z);
}
float weather_noise(vec2 p) {
    vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);
    return mix(mix(weather_hash(i),weather_hash(i+vec2(1,0)),f.x),
        mix(weather_hash(i+vec2(0,1)),weather_hash(i+1.0),f.x),f.y);
}
float weather_patch(vec2 p) {
    vec2 q=p/2.2;
    q+=vec2(weather_noise(p*.11),weather_noise(p*.13+17.0))*.3;
    vec2 id=floor(q),f=fract(q);
    float a=weather_hash(id+4.0),b=weather_hash(id+19.0);
    vec2 lo=vec2(.08+.23*a,.08+.24*b),hi=vec2(.91-.21*b,.92-.25*a);
    vec2 feather=max(vec2(.025),fwidth(q)*1.5);
    vec2 edges=smoothstep(lo,lo+feather,f)*(1.0-smoothstep(hi-feather,hi,f));
    return edges.x*edges.y*step(.66,weather_hash(id+33.0));
}
void surface_weather(vec3 p,vec3 normal,float height,inout vec3 albedo,inout vec3 packed,inout vec3 bump) {
    float amount=surface_effects.z*weather_features.x;
    if(amount<=0.0) return;
    float vertical=1.0-smoothstep(.34,.72,abs(normal.y));
    float horizontal=p.z*normal.x-p.x*normal.z;
    vec2 plane=mix(p.xz,vec2(horizontal,p.y),vertical);
    float macro=weather_noise(plane*.31+2.7)*.65+weather_noise(plane*.73+9.1)*.35;
    float broad=weather_noise(plane*.067+21.0);
    bool masonry=surface.x<.5 || (surface.x>4.5 && surface.x<8.5);
    float strength=masonry?.44:.23;
    albedo*=1.0+amount*((macro-.5)*strength+(broad-.5)*.28);
    albedo*=mix(vec3(1.0),vec3(1.04,1.0,.94),(broad-.5)*amount);
    packed.r=clamp(packed.r+(macro-.5)*.17*amount,0.04,1.0);
    // Sparse replastering and concrete repairs. Mortar, boards and grout keep
    // their authored layout; their base UVs are never randomly rotated.
    if(surface.x<.5 || (surface.x>4.5 && surface.x<6.5)) {
        float repair=weather_patch(plane)*vertical*amount;
        float sign=weather_hash(floor(plane/2.2)+52.0)>.48?1.0:-1.0;
        albedo*=1.0+repair*sign*.18;
        albedo*=mix(vec3(1),sign>0.0?vec3(.975,.988,1.02):vec3(1.03,1.008,.968),repair);
        packed.r=mix(packed.r,max(.3,packed.r-.10),repair);
        bump.xy*=1.0-.25*repair;
    }
    vec3 dust_colour=linear_colour(vec3(.57,.51,.41));
    vec3 grime_colour=linear_colour(vec3(.17,.15,.12));
    float dust=max(normal.y,0.0)*max(normal.y,0.0)*smoothstep(.27,.77,macro)*.24*amount;
    albedo=mix(albedo,dust_colour,dust);packed.r=mix(packed.r,.92,dust);packed.g*=1.0-dust;
    // Runoff starts at the actual box/ledge top, falls 0.15–1.65 m, and has
    // sparse columns with feathered sides. It cannot climb above its source.
    float column=horizontal*1.55;
    float cell=floor(column),lateral=fract(column);
    float seed=weather_hash(vec2(cell,floor(var_masks.w*2.0)));
    float bell=sin(lateral*3.14159265);bell*=bell;
    float below=var_masks.w-p.y;
    float runoff=smoothstep(0.0,.15,below)*(1.0-smoothstep(.15,1.65,below));
    float streak=runoff*bell*smoothstep(.30,.70,seed)*vertical*step(0.0,below)*amount;
    streak*=.65+.35*weather_noise(vec2(horizontal*12.0,p.y*3.0));
    vec3 run_colour=mix(albedo*.70,grime_colour,.25);
    run_colour=mix(run_colour,linear_colour(vec3(.34,.20,.11)),step(.88,seed)*.28);
    albedo=mix(albedo,run_colour,streak*.8);packed.r+=streak*.08;packed.g*=1.0-streak*.35;
    // World ground datum: street/yard elevation zero. Elevated room floors do
    // not acquire outdoor splash merely because they are the bottom of a box.
    float splash=vertical*(1.0-smoothstep(.05,.60,p.y))*(.55+.45*macro)*amount;
    albedo=mix(albedo,mix(grime_colour,dust_colour,.45),splash*.42);
    packed.r+=splash*.08;packed.g*=1.0-splash*.7;
    float cavity=(1.0-height)*(1.0-height)*.24*amount;
    float bottom=(1.0-smoothstep(0.0,.13,var_edges.z))*vertical;
    float grime=(bottom*var_masks.y+max(-normal.y,0.0)*.10)*amount;
    albedo=mix(albedo,grime_colour,clamp(cavity+grime*.35,0.0,.38));
    // Use max instead of multiplying two cavity occlusion terms: the baked
    // material cavities and mesh contact mask must not double-darken recesses.
    float mesh_occlusion=bottom*var_masks.z*amount;
    packed.b=1.0-max(1.0-packed.b,mesh_occlusion);
    float edge=min(min(var_edges.x,var_edges.y),min(var_edges.z,var_edges.w));
    float wear=(1.0-smoothstep(.008,.065,edge))*var_masks.x*amount;
    wear*=smoothstep(.25,.80,macro)*(.55+.45*smoothstep(.3,.8,height));
    bool coated=(surface.x>10.5 && surface.x<12.5) || (surface.x>16.5 && surface.x<17.5);
    vec3 worn=coated?linear_colour(vec3(.55,.57,.59)):mix(albedo,linear_colour(vec3(.62,.56,.46)),.45);
    albedo=mix(albedo,worn,wear*.65);packed.r=mix(packed.r,coated?.30:.58,wear*.65);
    if(coated) packed.g=mix(packed.g,1.0,wear*.65);
    packed=clamp(packed,vec3(.04,0,0),vec3(1));
}
