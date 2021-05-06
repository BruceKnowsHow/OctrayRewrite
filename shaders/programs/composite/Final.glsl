/*
const int colortex0Format = R32UI;
const bool colortex0Clear = true;
const vec4 colortex0ClearColor = vec4(0.0, 0.0, 0.0, 0.0);

const int colortex1Format = RGBA32F;
const bool colortex1Clear = true;
const vec4 colortex1ClearColor = vec4(0.0, 0.0, 0.0, 0.0);

const int colortex9Format = RGBA32F;
const bool colortex9Clear = false;

const int colortex6Format = RGBA8;
const int colortex7Format = RGB16F;
const int colortex8Format = RGBA8;
const int colortex10Format = RGB16F;
const int colortex12Format = RGB32F;
*/

uniform sampler2D colortex9;
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
    
    #ifdef DEBUG
    gl_FragColor.rgb = texelFetch(colortex5, ivec2(texcoord * viewSize), 0).rgb;
    #endif
}
