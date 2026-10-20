// Metal blends premultiplied linear light. The byte fallback compands colour
// before multiplying coverage: otherwise faint smoke has less than one RGB
// code value and forms coloured contour bands. Overlapping fallback layers
// blend in this encoded space (an explicit approximation); coverage stays linear.
vec4 store_transparency(vec3 premultiplied, float alpha) {
    if(colour_pipeline.x>.5) return vec4(premultiplied,alpha);
    vec3 colour=pow(clamp(premultiplied/(8.0*max(alpha,.0001)),0.0,1.0),vec3(.25))*alpha;
    vec4 value=vec4(colour,alpha);
    float noise=fract(52.9829189*fract(dot(gl_FragCoord.xy,vec2(0.06711056,0.00583715))));
    return floor(clamp(value,0.0,1.0)*255.0+noise)/255.0;
}
vec3 restore_transparency(vec4 value) {
    if(colour_pipeline.x>.5) return value.rgb;
    return pow(value.rgb/max(value.a,.0001),vec3(4.0))*8.0*value.a;
}
