#version 460
#include <flutter/runtime_effect.glsl>

out vec4 fragColor;

uniform vec2 uSize;
uniform sampler2D uTexture;
uniform float uBlendAlpha;
uniform vec2 uOffset;
uniform vec2 uScale;
uniform vec2 uAtlasSize;

void main() {
    // localUv is normalized to [0, 1] by dividing screen-space coords by uSize.
    vec2 localUv = FlutterFragCoord().xy / uSize;

    // Map local UV to global atlas coordinates.
    vec2 uv = localUv * uScale + uOffset;

    // Subtract half-pixel width boundary clamp to prevent texture bleeding from neighboring slots.
    vec2 halfPixel = vec2(0.5) / uAtlasSize;
    vec2 minUv = uOffset + halfPixel;
    vec2 maxUv = uOffset + uScale - halfPixel;
    
    // Clamp uv coordinates within the slot bounds with a half-pixel margin.
    uv = clamp(uv, minUv, maxUv);

    vec4 color = texture(uTexture, uv);
    fragColor = vec4(color.rgb, color.a * uBlendAlpha);
}
