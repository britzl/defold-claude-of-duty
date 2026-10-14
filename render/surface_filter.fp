varying highp vec2 var_uv;
uniform highp sampler2D source_texture;
uniform highp sampler2D height_texture;
uniform highp vec4 source_rect;
uniform highp vec4 filter_params; // output core size, operation, relief/metres, source core size
vec2 coord(vec2 uv) { return source_rect.xy+fract(uv)*source_rect.zw; }
float height_at(vec2 uv) {
    vec2 q=coord(uv);
    return texture2D(source_texture,q).a+(texture2D(height_texture,q).a-0.5)/255.0;
}
void main() {
    if (filter_params.y>2.5) { gl_FragColor=texture2D(source_texture,var_uv); return; }
    float size=filter_params.x;
    vec2 uv=(var_uv*(size+2.0)-1.0)/size;
    if(filter_params.y<0.5) gl_FragColor=texture2D(source_texture,coord(uv));
    else if(filter_params.y<1.5) {
        // Box filter in linear space; keep normal length (variance) for the
        // material shader's roughness correction at minified levels.
        vec2 d=vec2(0.5/filter_params.w);
        gl_FragColor=(texture2D(source_texture,coord(uv+vec2(-d.x,-d.y)))+
            texture2D(source_texture,coord(uv+vec2(d.x,-d.y)))+
            texture2D(source_texture,coord(uv+vec2(-d.x,d.y)))+
            texture2D(source_texture,coord(uv+d)))*0.25;
    } else {
        float t=1.0/filter_params.w;
        float a=height_at(uv+vec2(-t,-t)),b=height_at(uv+vec2(0,-t)),c=height_at(uv+vec2(t,-t));
        float d=height_at(uv+vec2(-t,0)),f=height_at(uv+vec2(t,0));
        float g=height_at(uv+vec2(-t,t)),h=height_at(uv+vec2(0,t)),i=height_at(uv+vec2(t,t));
        vec2 slope=vec2(c+2.0*f+i-a-2.0*d-g,g+2.0*h+i-a-2.0*b-c)*0.125/t;
        gl_FragColor=vec4(normalize(vec3(-slope*filter_params.z,1.0))*0.5+0.5,1.0);
    }
}
