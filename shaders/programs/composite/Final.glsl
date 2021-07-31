/* config
const int colortex0Format = R32UI;
const bool colortex0Clear = true;
const vec4 colortex0ClearColor = vec4(0.0, 0.0, 0.0, 0.0);

const int colortex1Format = RGBA32F;
const bool colortex1Clear = true;
const vec4 colortex1ClearColor = vec4(0.0, 0.0, 0.0, 0.0);

const int colortex2Format = R32UI;
const bool colortex2Clear = false;
const vec4 colortex2ClearColor = vec4(0.0, 0.0, 0.0, 0.0);

const int colortex3Format = R32UI;
const bool colortex3Clear = true;
const vec4 colortex3ClearColor = vec4(0.0, 0.0, 0.0, 0.0);

const int colortex5Format = RGBA8;
const bool colortex5Clear = true;
const vec4 colortex5ClearColor = vec4(0.0, 0.0, 0.0, 0.0);

const int colortex6Format = RGB32F;
const int colortex7Format = RGB32F;

const int colortex8Format = RGBA32F;
const int colortex9Format = RGBA32F;
const int colortex10Format = RGBA32F;
const int colortex11Format = RGBA32F;
const int colortex13Format = RGBA32F;
const bool colortex8Clear = false;
const bool colortex9Clear = false;
const bool colortex10Clear = false;
const bool colortex13Clear = false;
*/

layout (r32ui) uniform uimage2D colorimg2;

uniform sampler2D colortex13;
uniform sampler2D colortex8;
uniform sampler2D colortex5;
uniform sampler2D colortex6;
uniform sampler2D colortex10;
uniform sampler2D depthtex0;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferModelView;
uniform vec3 cameraPosition;
uniform vec2 viewSize;

uniform int hideGUI;

const bool colortex13MipmapEnabled = true;

vec2 texcoord = gl_FragCoord.xy / viewSize * MC_RENDER_QUALITY;

#include "../../includes/debug.glsl"

#include "../../includes/academy/aces.glsl"

void main() {
    vec3 avgCol = textureLod(colortex13, vec2(0.5), 16).rgb;
    float expo = pow(1.0 / sqrt(dot(avgCol, vec3(1.0))), 1.5);
    
    vec3 diffuse = texture(colortex13, texcoord).rgb;
    
    vec3 gbufferEncode = texelFetch(colortex6, ivec2(gl_FragCoord.xy), 0).rgb;
    vec3 albedo = unpackUnorm4x8(floatBitsToUint(gbufferEncode.r)).rgb * 256.0 / 255.0;
    
    albedo = pow(albedo, vec3(2.2));
    
    // vec3 color = diffuse * albedo;
    vec3 color = diffuse;
    
    color *= min(expo, 1000.0);
    vec3 sceneLDR = ACES_AP1_SRGB_RRT(color);
    
    color = ACES_AP1_SRGB_RRT(color);
    // WhiteBalance(color);
    // color    = Vibrance(color);
    // color    = Saturation(color);
    // color    = Contrast(color);
    // color    = LiftGammaGain(color);
    color = LinearToSRGB(color);
    
    gl_FragColor.rgb = color;
    
    if (int(gl_FragCoord.x) == 0 && int(gl_FragCoord.y) == 0)
        imageStore(colorimg2, ivec2(4095), uvec4(1));
    
    #ifdef DEBUG
    if (hideGUI == 1)
        gl_FragColor.rgb = imageLoad(colorimg5, ivec2(texcoord * viewSize)).rgb;
    #endif
}
