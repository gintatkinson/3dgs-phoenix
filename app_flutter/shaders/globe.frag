#version 460
#include <flutter/runtime_effect.glsl>

out vec4 fragColor;

uniform vec2 uSize;
uniform sampler2D uTexture;
uniform float uBlendAlpha;

void main() {
    vec2 uv = FlutterFragCoord().xy / uSize;
    vec4 color = texture(uTexture, uv);
    fragColor = vec4(color.rgb, color.a * uBlendAlpha);
}
