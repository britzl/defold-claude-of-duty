varying highp vec2 var_uv;
uniform highp vec4 bake;
#include "/render/surfaces.glsl"
void main() {
    vec3 albedo, packed; float height;
    surface_sample(var_uv,bake.y,albedo,height,packed);
    // Two RGBA8 alpha channels retain the height precision needed for relief
    // at 1K, without requiring a renderable float format on every backend.
    float high=floor(height*255.0+0.5);
    gl_FragColor=bake.x<0.5 ? vec4(albedo,high/255.0) : vec4(packed,height*255.0-high+0.5);
}
