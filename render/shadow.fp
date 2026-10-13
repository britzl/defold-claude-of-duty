varying highp float var_shadow_depth;
void main() {
    float d=clamp(var_shadow_depth,0.0,0.99999);
    vec2 packed=fract(d*vec2(1.0,255.0));
    packed.x-=packed.y/255.0;
    gl_FragColor=vec4(packed,0.0,1.0);
}
