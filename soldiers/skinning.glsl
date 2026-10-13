// Shared by the colour and shadow passes. 25 matrices = 100 vec4
// uniforms; no SSBO, bone texture or imported Model resource is required.
uniform highp mat4 bone_palette[25];
mat4 skin_matrix(vec4 joints, vec4 weights)
{
    return bone_palette[int(joints.x)] * weights.x
         + bone_palette[int(joints.y)] * weights.y
         + bone_palette[int(joints.z)] * weights.z
         + bone_palette[int(joints.w)] * weights.w;
}
