/*
layout (r32ui) uniform uimage2D colorimg0;
const int  colortex0Format = R32UI;
const bool colortex0Clear = true;
const vec4 colortex0ClearColor = vec4(0.0, 0.0, 0.0, 0.0);

layout (r32ui) uniform uimage2D colorimg1;
const int colortex1Format = R32UI;
const bool colortex1Clear = true;
const vec4 colortex1ClearColor = vec4(0.0, 0.0, 0.0, 0.0);

layout (rgba32f) uniform uimage2D colorimg2;
const int colortex2Format = RGBA32F;
const bool colortex2Clear = true;
const vec4 colortex2ClearColor = vec4(0.0, 0.0, 0.0, 0.0);

layout (r32i) uniform uimage2D colorimg3;
const int colortex3Format = R32I;
const bool colortex3Clear = true;
const vec4 colortex3ClearColor = vec4(0.0, 0.0, 0.0, 0.0);

layout (r32ui) uniform uimage2D colorimg4;
const int colortex4Format = R32UI;
const bool colortex4Clear = true;
const vec4 colortex4ClearColor = vec4(0.0, 0.0, 0.0, 0.0);

const int colortex9Format = RGBA32F;
const bool colortex9Clear = false;
const vec4 colortex9ClearColor = vec4(0.0, 0.0, 0.0, 0.0);

const int colortex6Format = RGBA8;
const int colortex7Format = RGB16F;
const int colortex8Format = RGBA8;
const int colortex10Format = RGB16F;
const int colortex12Format = RGB32F;
*/

uniform sampler2D colortex9;
uniform sampler2D colortex2;
layout (r32i) uniform iimage2D colorimg3;
uniform sampler2D colortex8;
uniform sampler2D colortex5;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferModelView;
uniform vec3 cameraPosition;
uniform vec2 viewSize;

const bool colortex9MipmapEnabled = true;

vec2 texcoord = gl_FragCoord.xy / viewSize * MC_RENDER_QUALITY;

#include "../../includes/Debug.glsl"

#include "../../includes/academy/aces.glsl"

void main() {
    vec3 avgCol = textureLod(colortex9, vec2(0.5), 16).rgb / textureLod(colortex9, vec2(0.5), 16).a;
    // float expo = pow(1.0 / dot(avgCol, vec3(3.0)), 0.7);
    float expo = pow(1.0 / dot(avgCol, vec3(1.0)), 0.9);
    
    vec4 color = texture(colortex9, texcoord);
    color.rgb /= color.a;
    color.rgb *= min(expo, 1000.0) * 2.0;
    vec3 sceneLDR = ACES_AP1_SRGB_RRT(color.rgb);
    
    color.rgb = ACES_AP1_SRGB_RRT(color.rgb);
    // WhiteBalance(color.rgb);
    // color.rgb    = Vibrance(color.rgb);
    // color.rgb    = Saturation(color.rgb);
    // color.rgb    = Contrast(color.rgb);
    // color.rgb    = LiftGammaGain(color.rgb);
    color.rgb = LinearToSRGB(color.rgb);
    color.rgb = pow(color.rgb, vec3(1.4));
    
    gl_FragColor.rgb = color.rgb;
    // gl_FragColor = vec4(imageLoad(colorimg3, ivec2(0, 0)).x / 1024 / 1024) / 20.0;
    
    #ifdef DEBUG
    gl_FragColor.rgb = texelFetch(colortex5, ivec2(texcoord * viewSize), 0).rgb;
    #endif
}
