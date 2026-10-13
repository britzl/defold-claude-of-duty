vec3 sky_radiance(vec3 direction)
{
    vec3 d = normalize(direction);
    float elevation = pow(max(d.y, 0.0), 0.45);
    vec3 sky = mix(vec3(0.78, 0.92, 1.10), vec3(0.12, 0.32, 0.72), elevation);
    float sun = max(dot(d, normalize(vec3(-0.6, 0.85, 0.4))), 0.0);
    sky += vec3(0.8, 0.59, 0.32) * pow(sun, 32.0);
    sky += vec3(6.0, 5.5, 4.2) * smoothstep(0.9994, 0.9998, sun);
    return mix(vec3(0.18, 0.145, 0.10), sky, smoothstep(-0.12, 0.02, d.y));
}
