#version 460
#include <flutter/runtime_effect.glsl>

out vec4 fragColor;

uniform vec2 uSize;
uniform vec3 uAtmosphereColor;
uniform float uGlowPower;

void main() {
    vec2 uv = (FlutterFragCoord().xy / uSize) - 0.5;
    float dist = length(uv);
    // Create a smooth atmosphere ring glow
    float glow = pow(smoothstep(0.5, 0.35, dist), uGlowPower);
    fragColor = vec4(uAtmosphereColor, glow);
}
