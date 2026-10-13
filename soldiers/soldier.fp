varying highp vec3 var_local;
varying mediump vec3 var_normal;
varying lowp vec4 var_color;
varying highp float var_depth;
void main()
{
    vec3 n = normalize(var_normal);
    vec3 p = var_local;
    float blotch = sin(p.x * 39.0 + sin(p.y * 32.0)) * sin(p.z * 31.0 + p.y * 28.0);
    float camo = mix(0.70, 1.10, smoothstep(-0.15, 0.28, blotch));
    vec3 albedo = var_color.rgb * mix(1.0, camo, var_color.a);
    float sun = max(dot(n, normalize(vec3(-0.6, 0.85, 0.4))), 0.0);
    vec3 ambient = mix(vec3(0.35, 0.30, 0.23), vec3(0.55, 0.62, 0.67), n.y * 0.5 + 0.5);
    vec3 lit = albedo * (ambient + vec3(0.70, 0.61, 0.46) * sun);
    gl_FragColor = vec4(mix(lit, vec3(0.66, 0.74, 0.77), smoothstep(25.0, 100.0, var_depth)), 1.0);
}
