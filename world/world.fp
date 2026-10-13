varying highp vec3 var_world;
varying mediump vec3 var_normal;
varying lowp vec4 var_color;
varying highp float var_depth;
uniform lowp vec4 surface;

float hash21(vec2 p)
{
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p)
{
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
               mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void main()
{
    vec3 n = normalize(var_normal);
    vec3 p = var_world;
    vec2 uv = abs(n.y) > 0.5 ? p.xz : (abs(n.x) > 0.5 ? p.zy : p.xy);
    float grain = noise(uv * 55.0);
    float patches = noise(uv * 1.6);
    float variation = 0.86 + patches * 0.15 + grain * 0.08;
    if (surface.x > 1.5 && surface.x < 2.5) {
        variation *= 0.82 + 0.18 * noise(vec2(uv.x * 35.0, uv.y * 1.5));
    }
    if (surface.x > 0.5 && surface.x < 1.5) {
        variation = 0.80 + 0.24 * grain + 0.08 * patches;
    }
    float sun = max(dot(n, normalize(vec3(-0.6, 0.85, 0.4))), 0.0);
    vec3 ambient = mix(vec3(0.35, 0.30, 0.23), vec3(0.55, 0.62, 0.67), n.y * 0.5 + 0.5);
    vec3 lit = var_color.rgb * variation * (ambient + vec3(0.70, 0.61, 0.46) * sun);
    float fog = smoothstep(25.0, 100.0, var_depth);
    gl_FragColor = vec4(mix(lit, vec3(0.66, 0.74, 0.77), fog), 1.0);
}
