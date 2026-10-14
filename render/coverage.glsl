// Shared binary coverage for generated perforated surfaces. Vertex alpha=1 is
// solid; values below 1 open circular holes on a 30 cm world-anchored grid.
// The exact same function and unmodified geometry feed colour and depth passes.
void surface_clip(vec3 p,vec3 n,float coverage) {
    if(coverage>=.999) return;
    if(coverage<=0.0) discard;
    vec3 a=abs(n);
    vec2 uv=a.y>.5?p.xz:a.x>.5?p.zy:p.xy;
    vec2 cell=fract(uv/.3)-.5;
    if(length(cell)<.48*sqrt(1.0-coverage)) discard;
}
