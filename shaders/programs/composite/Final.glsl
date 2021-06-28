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
const bool colortex8Clear = false;
const bool colortex9Clear = false;
const bool colortex10Clear = false;
*/

layout (r32ui) uniform uimage2D colorimg2;

uniform sampler2D colortex9;
uniform sampler2D colortex8;
uniform sampler2D colortex5;
uniform sampler2D colortex6;
uniform sampler2D colortex10;
uniform sampler2D depthtex0;
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
    float expo = pow(1.0 / dot(avgCol, vec3(1.0)), 1.0);
    
    vec4 color = texture(colortex9, texcoord);
    
    vec4 diffuse = texelFetch(colortex10, ivec2(gl_FragCoord.xy), 0); diffuse.rgb /= diffuse.a;
    diffuse.rgb = pow(diffuse.rgb, vec3(2.2));
    color.rgb *= max(diffuse.rgb, vec3(0.001));
    
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
    // color.rgb = pow(color.rgb, vec3(1.0/2.2));
    
    gl_FragColor.rgb = color.rgb;
    
    if (int(gl_FragCoord.x) == 0 && int(gl_FragCoord.y) == 0)
        imageStore(colorimg2, ivec2(4095), uvec4(1));
    
    #ifdef DEBUG
    gl_FragColor.rgb = imageLoad(colorimg5, ivec2(texcoord * viewSize)).rgb;
    #endif
}
