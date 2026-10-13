varying mediump vec3 var_normal;
varying lowp vec4 var_color;
uniform lowp vec4 tint;
uniform mediump vec4 light_dir;
void main() {
    vec3 n = normalize(var_normal);
    float sun = max(dot(n, normalize(light_dir.xyz)), 0.0);
    vec3 ambient = mix(vec3(0.35, 0.30, 0.23), vec3(0.55, 0.62, 0.67), n.y * 0.5 + 0.5);
    vec3 lit = var_color.rgb * tint.rgb * (ambient + vec3(0.70, 0.61, 0.46) * sun);
    gl_FragColor = vec4(mix(lit, var_color.rgb * tint.rgb, tint.w), 1.0);
}
