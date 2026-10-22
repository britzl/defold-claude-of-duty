// Deterministic Hammersley sequence without integer/bitwise GLSL requirements.
vec2 sample_point(int index) {
    float n=float(index),r=0.0,p=.5;
    for(int bit=0;bit<7;bit++) { r+=mod(n,2.0)*p;n=floor(n*.5);p*=.5; }
    return vec2((float(index)+.5)/128.0,r);
}
