varying highp vec2 var_uv;
uniform highp sampler2D source_texture;
uniform highp sampler2D scattering_texture;
uniform highp sampler2D scattering_fine_texture;
void main() {
    gl_FragData[0]=texture2D(source_texture,var_uv);
    gl_FragData[1]=texture2D(scattering_texture,var_uv);
    gl_FragData[2]=texture2D(scattering_fine_texture,var_uv);
}
