const float PI=3.14159265;
float ggx_g1(float nx,float alpha2) {
    return 2.0*nx/max(nx+sqrt(alpha2+(1.0-alpha2)*nx*nx),.00001);
}
vec3 ggx_half(vec2 xi,float roughness) {
    float a=max(roughness*roughness,.0001),a2=a*a;
    float c=sqrt((1.0-xi.y)/(1.0+(a2-1.0)*xi.y));
    float s=sqrt(max(0.0,1.0-c*c)),phi=2.0*PI*xi.x;
    return vec3(cos(phi)*s,sin(phi)*s,c);
}
