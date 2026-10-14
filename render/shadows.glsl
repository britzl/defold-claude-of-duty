uniform highp sampler2D shadow_texture;
uniform highp vec4 features; // shadow, normals, local lights, fog
// Three orthographic rows + (world texel, inverse depth range, far, blend start)
// per cascade, followed by world->camera depth and (atlas texel, tile texel, softness, debug).
uniform highp vec4 shadow_data[18];
vec2 shadow_tile(int c) { return vec2(mod(float(c),2.0),floor(float(c)*.5))*.5; }
float shadow_depth(int c,vec2 uv) {
    vec2 base=shadow_tile(c);
    vec2 at=clamp(base+uv*.5,base+vec2(shadow_data[17].x*.5),base+vec2(.5-shadow_data[17].x*.5));
    vec2 packed=texture2D(shadow_texture,at).rg;
    return packed.x+packed.y/255.0;
}
// Interpolate comparison results, never packed depth. This keeps sub-texel
// camera motion continuous on every backend, without hardware compare samplers.
float shadow_compare(int c,vec2 uv,float receiver) {
    float size=1.0/shadow_data[17].y;
    vec2 p=uv*size-.5,f=fract(p),base=(floor(p)+.5)/size;
    float a=step(receiver,shadow_depth(c,base));
    float b=step(receiver,shadow_depth(c,base+vec2(1.0,0.0)/size));
    float d=step(receiver,shadow_depth(c,base+vec2(0.0,1.0)/size));
    float e=step(receiver,shadow_depth(c,base+vec2(1.0)/size));
    return mix(mix(a,b,f.x),mix(d,e,f.x),f.y);
}
vec2 shadow_disk(int i) {
    float a=float(i)*2.39996323;
    return vec2(cos(a),sin(a))*sqrt((float(i)+.5)/8.0);
}
float shadow_cascade(int c,vec3 p,vec3 geometric) {
    vec4 info=shadow_data[c*4+3];
    float nl=clamp(dot(geometric,normalize(sun_direction.xyz)),0.0,1.0);
    float slope=min(3.0,sqrt(max(0.0,1.0-nl*nl))/max(nl,.2));
    vec4 position=vec4(p+geometric*info.x*(.35+.65*(1.0-nl)),1.0);
    vec3 coord=vec3(dot(shadow_data[c*4],position),dot(shadow_data[c*4+1],position),dot(shadow_data[c*4+2],position))*.5+.5;
    if(any(lessThan(coord,vec3(0.0))) || any(greaterThan(coord,vec3(1.0)))) return 1.0;
    float receiver=coord.z-info.x*(.35+.65*slope)*info.y-1.0/65025.0;
    float blocker=0.0,count=0.0;
    for(int i=0;i<8;i++) {
        float d=shadow_depth(c,coord.xy+shadow_disk(i)*4.0*shadow_data[17].y);
        if(d<receiver) { blocker+=d;count+=1.0; }
    }
    // A fixed, light-space kernel avoids screen-noise shimmer before TAA exists.
    float gap=count>0.0?max(0.0,(receiver-blocker/max(count,1.0))/info.y):0.0;
    float radius=clamp(gap*shadow_data[17].z/info.x,1.0,4.0)*shadow_data[17].y;
    float sum=0.0;
    for(int y=-1;y<=1;y++) for(int x=-1;x<=1;x++) {
        float weight=(x==0?2.0:1.0)*(y==0?2.0:1.0);
        sum+=weight*shadow_compare(c,coord.xy+vec2(float(x),float(y))*radius,receiver);
    }
    return sum/16.0;
}
int shadow_index(float depth) {
    if(depth<shadow_data[3].z) return 0;
    if(depth<shadow_data[7].z) return 1;
    if(depth<shadow_data[11].z) return 2;
    return 3;
}
float shadow_visibility(vec3 p,vec3 geometric) {
    if(features.x<.5) return 1.0;
    float depth=dot(shadow_data[16],vec4(p,1.0));
    if(depth>=shadow_data[15].z) return 1.0;
    int c=shadow_index(depth);
    float visibility=shadow_cascade(c,p,geometric);
    vec4 info=shadow_data[c*4+3];
    float blend=smoothstep(info.w,info.z,depth);
    if(c<3 && blend>0.0) visibility=mix(visibility,shadow_cascade(c+1,p,geometric),blend);
    if(c==3) visibility=mix(visibility,1.0,blend);
    return visibility;
}
vec3 shadow_debug(vec3 p,float visibility) {
    if(shadow_data[17].w>1.5) return vec3(visibility);
    float depth=dot(shadow_data[16],vec4(p,1.0));
    int c=shadow_index(depth);
    vec3 tint=c==0?vec3(.8,.15,.1):c==1?vec3(.15,.8,.1):c==2?vec3(.1,.3,.8):vec3(.8,.15,.8);
    vec3 next=c==0?vec3(.15,.8,.1):c==1?vec3(.1,.3,.8):c==2?vec3(.8,.15,.8):vec3(.4);
    vec4 info=shadow_data[c*4+3];
    return mix(tint,next,smoothstep(info.w,info.z,depth))*(.25+.75*visibility);
}
