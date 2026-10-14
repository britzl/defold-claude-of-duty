uniform highp vec4 light_positions[4]; // xyz, radius
uniform lowp sampler2D local_shadow_texture;
uniform highp vec4 local_shadow_params; // enabled, tile size, reserved
uniform highp vec4 light_shadow_slots; // receiver slot, fade, receiver slot, fade
float local_visibility(int light,vec3 p,vec3 n) {
    if(local_shadow_params.x<.5) return 1.0;
    float cube=-1.0,gain=0.0;
    if(abs(float(light)-light_shadow_slots.x)<.1) {cube=0.0;gain=light_shadow_slots.y;}
    if(abs(float(light)-light_shadow_slots.z)<.1) {cube=1.0;gain=light_shadow_slots.w;}
    if(cube<0.0 || gain<=0.0) return 1.0;
    vec3 delta=p+normalize(n)*.025-light_positions[light].xyz;
    float radius=light_positions[light].w;
    vec3 a=abs(delta);vec2 uv;float face;
    if(a.x>=a.y && a.x>=a.z) {face=delta.x>0.0?0.0:1.0;uv=vec2(delta.x>0.0?-delta.z:delta.z,-delta.y)/a.x;}
    else if(a.y>=a.z) {face=delta.y>0.0?2.0:3.0;uv=vec2(delta.x,delta.y>0.0?delta.z:-delta.z)/a.y;}
    else {face=delta.z>0.0?4.0:5.0;uv=vec2(delta.z>0.0?delta.x:-delta.x,-delta.y)/a.z;}
    vec2 tile=vec2(mod(face,3.0),floor(face/3.0)+cube*2.0);
    float size=local_shadow_params.y;
    vec2 pixel=(uv*.5+.5)*size;
    float depth=(length(delta)-.025)/max(radius,.001),visible=0.0;
    for(int y=-1;y<=1;y++) for(int x=-1;x<=1;x++) {
        vec2 q=(tile*size+clamp(pixel+vec2(float(x),float(y)),vec2(.5),vec2(size-.5)))/(size*vec2(3,4));
        vec2 packed=texture2D(local_shadow_texture,q).rg;
        visible+=step(depth,packed.r+packed.g/255.0);
    }
    return mix(1.0,visible/9.0,gain);
}
