varying highp vec2 var_uv;
uniform highp sampler2D source_texture;
uniform highp sampler2D source_depth;
void main() {
    gl_FragColor=texture2D(source_texture,var_uv);
    // Restore the actual depth attachment, not the quantized colour encoding,
    // so animated casters have precisely the same depth test as a fresh map.
    gl_FragDepth=texture2D(source_depth,var_uv).r;
}
