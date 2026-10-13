varying mediump vec2 var_uv;
uniform lowp sampler2D weapon_texture;
void main() { gl_FragColor = texture2D(weapon_texture, var_uv); }
